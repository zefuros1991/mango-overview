#include "captureclient.hpp"

#include <cstring>

#include <QAbstractEventDispatcher>
#include <QCoreApplication>
#include <QLoggingCategory>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>

#include "ext-foreign-toplevel-list-v1-client-protocol.h"
#include "ext-image-capture-source-v1-client-protocol.h"
#include "ext-image-copy-capture-v1-client-protocol.h"

Q_LOGGING_CATEGORY(logCapture, "mangooverview.capture", QtInfoMsg);

namespace {

// ---- toplevel list -------------------------------------------------------

const ext_foreign_toplevel_handle_v1_listener handleListener = {
    .closed = [](void* data, ext_foreign_toplevel_handle_v1*) {
	    auto* t = static_cast<ToplevelHandle*>(data);
	    t->client->onToplevelClosed(t);
    },
    .done = [](void* data, ext_foreign_toplevel_handle_v1*) {
	    auto* t = static_cast<ToplevelHandle*>(data);
	    t->client->onToplevelDone(t);
    },
    .title = [](void*, ext_foreign_toplevel_handle_v1*, const char*) {},
    .app_id = [](void*, ext_foreign_toplevel_handle_v1*, const char*) {},
    .identifier = [](void* data, ext_foreign_toplevel_handle_v1*, const char* identifier) {
	    auto* t = static_cast<ToplevelHandle*>(data);
	    t->client->onToplevelIdentifier(t, identifier);
    },
};

const ext_foreign_toplevel_list_v1_listener listListener = {
    .toplevel = [](void* data, ext_foreign_toplevel_list_v1*, ext_foreign_toplevel_handle_v1* handle) {
	    static_cast<CaptureClient*>(data)->onToplevel(handle);
    },
    .finished = [](void*, ext_foreign_toplevel_list_v1*) {},
};

const wl_registry_listener registryListener = {
    .global = [](void* data, wl_registry* registry, uint32_t name, const char* interface, uint32_t version) {
	    static_cast<CaptureClient*>(data)->onGlobal(registry, name, interface, version);
    },
    .global_remove = [](void*, wl_registry*, uint32_t) {},
};

// ---- capture session -----------------------------------------------------

const ext_image_copy_capture_session_v1_listener sessionListener = {
    .buffer_size = [](void* data, ext_image_copy_capture_session_v1*, uint32_t w, uint32_t h) {
	    static_cast<CaptureSession*>(data)->onBufferSize(w, h);
    },
    .shm_format = [](void* data, ext_image_copy_capture_session_v1*, uint32_t format) {
	    static_cast<CaptureSession*>(data)->onShmFormat(format);
    },
    .dmabuf_device = [](void*, ext_image_copy_capture_session_v1*, wl_array*) {},
    .dmabuf_format = [](void*, ext_image_copy_capture_session_v1*, uint32_t, wl_array*) {},
    .done = [](void* data, ext_image_copy_capture_session_v1*) {
	    static_cast<CaptureSession*>(data)->onDone();
    },
    .stopped = [](void* data, ext_image_copy_capture_session_v1*) {
	    static_cast<CaptureSession*>(data)->onStopped();
    },
};

const ext_image_copy_capture_frame_v1_listener frameListener = {
    .transform = [](void*, ext_image_copy_capture_frame_v1*, uint32_t) {},
    .damage = [](void*, ext_image_copy_capture_frame_v1*, int32_t, int32_t, int32_t, int32_t) {},
    .presentation_time = [](void*, ext_image_copy_capture_frame_v1*, uint32_t, uint32_t, uint32_t) {},
    .ready = [](void* data, ext_image_copy_capture_frame_v1*) {
	    static_cast<CaptureSession*>(data)->onReady();
    },
    .failed = [](void* data, ext_image_copy_capture_frame_v1*, uint32_t reason) {
	    static_cast<CaptureSession*>(data)->onFailed(reason);
    },
};

// Formats we can hand to QImage without converting, best first.
QImage::Format qimageFormat(uint32_t format) {
	switch (format) {
	case WL_SHM_FORMAT_XRGB8888: return QImage::Format_RGB32;
	case WL_SHM_FORMAT_ARGB8888: return QImage::Format_ARGB32_Premultiplied;
	case WL_SHM_FORMAT_XBGR8888: return QImage::Format_RGBX8888;
	case WL_SHM_FORMAT_ABGR8888: return QImage::Format_RGBA8888_Premultiplied;
	default: return QImage::Format_Invalid;
	}
}

// With alpha first: see-through windows (a terminal with a translucent
// background) then show the card's wallpaper behind them, like on the real
// desktop. Without alpha, Hyprland fills the see-through parts with whatever
// it last drew behind the window, which shows up as ghost text.
const uint32_t preferredFormats[] = {
    WL_SHM_FORMAT_ARGB8888,
    WL_SHM_FORMAT_ABGR8888,
    WL_SHM_FORMAT_XRGB8888,
    WL_SHM_FORMAT_XBGR8888,
};

} // namespace

// ==== CaptureClient ========================================================

CaptureClient* CaptureClient::instance() {
	static auto* client = new CaptureClient();
	return client;
}

CaptureClient::CaptureClient(): QObject(QCoreApplication::instance()) {
	this->display = wl_display_connect(nullptr);
	if (!this->display) {
		qCWarning(logCapture) << "Could not connect to the Wayland compositor.";
		return;
	}

	this->registry = wl_display_get_registry(this->display);
	wl_registry_add_listener(this->registry, &registryListener, this);
	wl_display_roundtrip(this->display); // globals
	wl_display_roundtrip(this->display); // initial toplevels and their identifiers

	if (!this->isActive()) {
		qCWarning(logCapture) << "Compositor lacks ext-foreign-toplevel-list, "
		                         "ext-foreign-toplevel-image-capture-source or ext-image-copy-capture; "
		                         "window capture is disabled.";
	}

	this->notifier =
	    new QSocketNotifier(wl_display_get_fd(this->display), QSocketNotifier::Read, this);
	QObject::connect(this->notifier, &QSocketNotifier::activated, this, &CaptureClient::dispatch);

	// Send queued requests before the event loop goes to sleep.
	QObject::connect(
	    QAbstractEventDispatcher::instance(),
	    &QAbstractEventDispatcher::aboutToBlock,
	    this,
	    &CaptureClient::flush
	);
}

bool CaptureClient::isActive() const {
	return this->shm && this->sourceManager && this->copyManager && this->toplevelList;
}

void CaptureClient::flush() {
	if (this->display) wl_display_flush(this->display);
}

void CaptureClient::dispatch() {
	if (wl_display_dispatch(this->display) == -1) {
		qCWarning(logCapture) << "Lost the Wayland connection; window capture stopped.";
		this->notifier->setEnabled(false);
		return;
	}
	this->flush();
}

void CaptureClient::onGlobal(wl_registry* registry, uint32_t name, const char* interface, uint32_t version) {
	auto is = [&](const wl_interface& i) { return std::strcmp(interface, i.name) == 0; };

	if (is(wl_shm_interface)) {
		this->shm = static_cast<wl_shm*>(wl_registry_bind(registry, name, &wl_shm_interface, 1));
	} else if (is(ext_foreign_toplevel_list_v1_interface)) {
		this->toplevelList = static_cast<ext_foreign_toplevel_list_v1*>(
		    wl_registry_bind(registry, name, &ext_foreign_toplevel_list_v1_interface, 1)
		);
		ext_foreign_toplevel_list_v1_add_listener(this->toplevelList, &listListener, this);
	} else if (is(ext_foreign_toplevel_image_capture_source_manager_v1_interface)) {
		this->sourceManager = static_cast<ext_foreign_toplevel_image_capture_source_manager_v1*>(
		    wl_registry_bind(registry, name, &ext_foreign_toplevel_image_capture_source_manager_v1_interface, 1)
		);
	} else if (is(ext_image_copy_capture_manager_v1_interface)) {
		this->copyManager = static_cast<ext_image_copy_capture_manager_v1*>(
		    wl_registry_bind(registry, name, &ext_image_copy_capture_manager_v1_interface, 1)
		);
	}
	Q_UNUSED(version);
}

void CaptureClient::onToplevel(ext_foreign_toplevel_handle_v1* handle) {
	auto* toplevel = new ToplevelHandle {.client = this, .handle = handle};
	ext_foreign_toplevel_handle_v1_add_listener(handle, &handleListener, toplevel);
	this->toplevels.append(toplevel);
}

void CaptureClient::onToplevelIdentifier(ToplevelHandle* toplevel, const char* identifier) {
	toplevel->identifier = QString::fromUtf8(identifier);
}

void CaptureClient::onToplevelDone(ToplevelHandle* toplevel) {
	if (toplevel->identifier.isEmpty() || this->byIdentifier.contains(toplevel->identifier)) return;
	this->byIdentifier.insert(toplevel->identifier, toplevel);
	emit this->toplevelAdded(toplevel->identifier);
}

void CaptureClient::onToplevelClosed(ToplevelHandle* toplevel) {
	this->byIdentifier.remove(toplevel->identifier);
	this->toplevels.removeOne(toplevel);
	ext_foreign_toplevel_handle_v1_destroy(toplevel->handle);
	delete toplevel;
}

CaptureSession* CaptureClient::capture(const QString& identifier, bool paintCursors) {
	if (!this->isActive()) return nullptr;
	auto* toplevel = this->byIdentifier.value(identifier);
	if (!toplevel) return nullptr;
	return new CaptureSession(this, toplevel->handle, paintCursors);
}

// ==== CaptureSession =======================================================

CaptureSession::CaptureSession(
    CaptureClient* client,
    ext_foreign_toplevel_handle_v1* handle,
    bool paintCursors
)
    : client(client) {
	this->source = ext_foreign_toplevel_image_capture_source_manager_v1_create_source(
	    client->sourceManager,
	    handle
	);
	this->session = ext_image_copy_capture_manager_v1_create_session(
	    client->copyManager,
	    this->source,
	    paintCursors ? EXT_IMAGE_COPY_CAPTURE_MANAGER_V1_OPTIONS_PAINT_CURSORS : 0
	);
	ext_image_copy_capture_session_v1_add_listener(this->session, &sessionListener, this);
	client->flush();
}

CaptureSession::~CaptureSession() {
	if (this->currentFrame) ext_image_copy_capture_frame_v1_destroy(this->currentFrame);
	if (this->session) ext_image_copy_capture_session_v1_destroy(this->session);
	if (this->source) ext_image_capture_source_v1_destroy(this->source);
	this->destroyBuffer();
	this->client->flush();
}

void CaptureSession::setLive(bool live) {
	this->live = live;
	if (live) this->requestFrame();
}

void CaptureSession::requestFrame() {
	this->wantFrame = true;
	this->startFrame();
}

void CaptureSession::onBufferSize(uint32_t width, uint32_t height) {
	this->pendingWidth = width;
	this->pendingHeight = height;
}

void CaptureSession::onShmFormat(uint32_t format) { this->pendingFormats.append(format); }

void CaptureSession::onDone() {
	// The compositor (re)sent the buffer constraints; a new buffer may be needed.
	uint32_t chosen = 0;
	bool found = false;
	for (auto f: preferredFormats) {
		if (this->pendingFormats.contains(f)) {
			chosen = f;
			found = true;
			break;
		}
	}
	this->pendingFormats.clear();

	if (!found) {
		qCWarning(logCapture) << "No supported shm format offered for window capture.";
		return;
	}

	if (!this->buffer || chosen != this->format || this->pendingWidth != this->width
	    || this->pendingHeight != this->height)
	{
		this->destroyBuffer();
		this->format = chosen;
		this->width = this->pendingWidth;
		this->height = this->pendingHeight;
	}

	this->constraintsKnown = true;
	this->startFrame();
}

void CaptureSession::onStopped() {
	this->isStopped = true;
	emit this->stopped();
}

void CaptureSession::onReady() {
	ext_image_copy_capture_frame_v1_destroy(this->currentFrame);
	this->currentFrame = nullptr;

	// Copy out: the buffer is reused for the next frame.
	auto image = QImage(
	                 static_cast<const uchar*>(this->data),
	                 static_cast<int>(this->width),
	                 static_cast<int>(this->height),
	                 static_cast<qsizetype>(this->stride),
	                 qimageFormat(this->format)
	)
	                 .copy();

	this->wantFrame = this->live;
	// A window can hand back an empty frame (no buffer yet); passing it on
	// would wipe the last good picture and leave the card blank.
	if (!image.isNull()) emit this->frame(image);
	this->startFrame();
}

void CaptureSession::onFailed(uint32_t reason) {
	ext_image_copy_capture_frame_v1_destroy(this->currentFrame);
	this->currentFrame = nullptr;
	// The frame never arrived, so it is still wanted. Without this a window
	// that was resized (new buffer constraints) froze at its old picture.
	this->wantFrame = true;

	switch (reason) {
	case EXT_IMAGE_COPY_CAPTURE_FRAME_V1_FAILURE_REASON_BUFFER_CONSTRAINTS:
		// New constraints follow with another done event; wait for it.
		this->constraintsKnown = false;
		break;
	case EXT_IMAGE_COPY_CAPTURE_FRAME_V1_FAILURE_REASON_STOPPED:
		this->onStopped();
		break;
	default: this->startFrame(); break;
	}
}

bool CaptureSession::createBuffer() {
	this->stride = this->width * 4;
	this->dataSize = static_cast<size_t>(this->stride) * this->height;
	if (this->dataSize == 0) return false;

	int fd = memfd_create("mango-overview-capture", MFD_CLOEXEC);
	if (fd == -1) return false;

	if (ftruncate(fd, static_cast<off_t>(this->dataSize)) == -1) {
		close(fd);
		return false;
	}

	this->data = mmap(nullptr, this->dataSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (this->data == MAP_FAILED) {
		this->data = nullptr;
		close(fd);
		return false;
	}

	auto* pool = wl_shm_create_pool(this->client->shm, fd, static_cast<int32_t>(this->dataSize));
	this->buffer = wl_shm_pool_create_buffer(
	    pool,
	    0,
	    static_cast<int32_t>(this->width),
	    static_cast<int32_t>(this->height),
	    static_cast<int32_t>(this->stride),
	    this->format
	);
	wl_shm_pool_destroy(pool);
	close(fd);
	return true;
}

void CaptureSession::destroyBuffer() {
	if (this->buffer) wl_buffer_destroy(this->buffer);
	if (this->data) munmap(this->data, this->dataSize);
	this->buffer = nullptr;
	this->data = nullptr;
	this->dataSize = 0;
}

void CaptureSession::startFrame() {
	if (this->isStopped || this->currentFrame || !this->wantFrame || !this->constraintsKnown) return;
	if (!this->buffer && !this->createBuffer()) return;

	this->wantFrame = false;
	this->currentFrame = ext_image_copy_capture_session_v1_create_frame(this->session);
	ext_image_copy_capture_frame_v1_add_listener(this->currentFrame, &frameListener, this);
	ext_image_copy_capture_frame_v1_attach_buffer(this->currentFrame, this->buffer);
	ext_image_copy_capture_frame_v1_damage_buffer(
	    this->currentFrame,
	    0,
	    0,
	    static_cast<int32_t>(this->width),
	    static_cast<int32_t>(this->height)
	);
	// The compositor answers when the window next changes, so a live capture
	// paces itself: no polling, no repeated identical frames.
	ext_image_copy_capture_frame_v1_capture(this->currentFrame);
	this->client->flush();
}
