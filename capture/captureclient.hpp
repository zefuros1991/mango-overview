#pragma once

// Our own Wayland connection to the compositor, used only for window capture.
// It is separate from Qt's connection, so it needs nothing from Qt's internals.

#include <QHash>
#include <QImage>
#include <QObject>
#include <QPointer>
#include <QSocketNotifier>

struct wl_display;
struct wl_registry;
struct wl_shm;
struct wl_buffer;
struct ext_foreign_toplevel_list_v1;
struct ext_foreign_toplevel_handle_v1;
struct ext_foreign_toplevel_image_capture_source_manager_v1;
struct ext_image_copy_capture_manager_v1;
struct ext_image_capture_source_v1;
struct ext_image_copy_capture_session_v1;
struct ext_image_copy_capture_frame_v1;

class CaptureClient;

struct ToplevelHandle {
	CaptureClient* client = nullptr;
	ext_foreign_toplevel_handle_v1* handle = nullptr;
	QString identifier;
	bool closed = false;
};

// One running capture of one window. Delivers a new QImage each time the window changes.
class CaptureSession: public QObject {
	Q_OBJECT;

public:
	CaptureSession(CaptureClient* client, ext_foreign_toplevel_handle_v1* handle, bool paintCursors);
	~CaptureSession() override;

	void setLive(bool live);
	void requestFrame();

	// Wayland callbacks.
	void onBufferSize(uint32_t width, uint32_t height);
	void onShmFormat(uint32_t format);
	void onDone();
	void onStopped();
	void onReady();
	void onFailed(uint32_t reason);

signals:
	void frame(const QImage& image);
	void stopped();

private:
	void destroyBuffer();
	bool createBuffer();
	void startFrame();

	CaptureClient* client;
	ext_image_capture_source_v1* source = nullptr;
	ext_image_copy_capture_session_v1* session = nullptr;
	ext_image_copy_capture_frame_v1* currentFrame = nullptr;

	// Constraints as last advertised (pending) and as used by the current buffer.
	uint32_t pendingWidth = 0, pendingHeight = 0;
	QList<uint32_t> pendingFormats;
	bool constraintsKnown = false;

	wl_buffer* buffer = nullptr;
	void* data = nullptr;
	size_t dataSize = 0;
	uint32_t width = 0, height = 0, stride = 0, format = 0;

	bool live = true;
	bool wantFrame = false;
	bool isStopped = false;
};

class CaptureClient: public QObject {
	Q_OBJECT;

public:
	static CaptureClient* instance();

	[[nodiscard]] bool isActive() const;
	// nullptr if no window has this identifier (yet).
	CaptureSession* capture(const QString& identifier, bool paintCursors);
	void flush();

	wl_shm* shm = nullptr;
	ext_foreign_toplevel_image_capture_source_manager_v1* sourceManager = nullptr;
	ext_image_copy_capture_manager_v1* copyManager = nullptr;

	// Wayland callbacks.
	void onGlobal(wl_registry* registry, uint32_t name, const char* interface, uint32_t version);
	void onToplevel(ext_foreign_toplevel_handle_v1* handle);
	void onToplevelIdentifier(ToplevelHandle* toplevel, const char* identifier);
	void onToplevelDone(ToplevelHandle* toplevel);
	void onToplevelClosed(ToplevelHandle* toplevel);

signals:
	// A window with this identifier appeared, so a waiting capture can start.
	void toplevelAdded(const QString& identifier);

private:
	CaptureClient();
	void dispatch();

	wl_display* display = nullptr;
	wl_registry* registry = nullptr;
	ext_foreign_toplevel_list_v1* toplevelList = nullptr;
	QSocketNotifier* notifier = nullptr;
	QList<ToplevelHandle*> toplevels;
	QHash<QString, ToplevelHandle*> byIdentifier;
};
