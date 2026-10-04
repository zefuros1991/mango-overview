#include "windowcapture.hpp"

#include <QQuickWindow>
#include <QTimer>
#include <QSGSimpleTextureNode>
#include <QSGTexture>

#include "captureclient.hpp"

WindowCapture::WindowCapture(QQuickItem* parent): QQuickItem(parent) {
	this->setFlag(QQuickItem::ItemHasContents);
}

WindowCapture::~WindowCapture() { this->stop(); }

void WindowCapture::setIdentifier(const QString& identifier) {
	if (identifier == this->mIdentifier) return;
	this->mIdentifier = identifier;
	emit this->identifierChanged();
	if (this->isComponentComplete()) this->restart();
}

void WindowCapture::setLive(bool live) {
	if (live == this->mLive) return;
	this->mLive = live;
	emit this->liveChanged();
	this->updateLive();
}

void WindowCapture::setPaintCursor(bool paintCursor) {
	if (paintCursor == this->mPaintCursor) return;
	this->mPaintCursor = paintCursor;
	emit this->paintCursorChanged();
	if (this->isComponentComplete()) this->restart();
}

void WindowCapture::componentComplete() {
	QQuickItem::componentComplete();
	this->restart();
}

void WindowCapture::itemChange(ItemChange change, const ItemChangeData& value) {
	QQuickItem::itemChange(change, value);
	// Hidden thumbnails stop pulling frames.
	if (change == ItemVisibleHasChanged) this->updateLive();
}

void WindowCapture::captureFrame() {
	// No session (the compositor ended it): a new one sends a first frame.
	if (this->session) this->session->requestFrame();
	else if (this->isComponentComplete()) this->restart();
}

void WindowCapture::stop() {
	delete this->session;
	this->session = nullptr;
}

void WindowCapture::restart() {
	this->stop();
	auto* client = CaptureClient::instance();
	QObject::disconnect(client, &CaptureClient::toplevelAdded, this, &WindowCapture::onToplevelAdded);
	if (this->mIdentifier.isEmpty()) return;

	this->session = client->capture(this->mIdentifier, this->mPaintCursor);
	if (!this->session) {
		// Window not announced yet (it may have just opened): wait for it.
		QObject::connect(client, &CaptureClient::toplevelAdded, this, &WindowCapture::onToplevelAdded);
		return;
	}

	QObject::connect(this->session, &CaptureSession::frame, this, &WindowCapture::onFrame);
	QObject::connect(this->session, &CaptureSession::stopped, this, &WindowCapture::onStopped);
	this->session->requestFrame(); // always show at least one frame
	this->gotFrame = false;
	// A session started while the window is in flight (just moved to another
	// workspace) can stay silent forever on Hyprland, leaving a blank tile.
	// If no first frame comes, start over a few times.
	QPointer<CaptureSession> started = this->session;
	QTimer::singleShot(1000, this, [this, started] {
		if (!this->gotFrame && this->mWanted && this->session == started && this->retries < 6) {
			this->retries++;
			this->restart();
		}
	});
	this->updateLive();
}

void WindowCapture::updateLive() {
	auto wanted = this->mLive && this->isVisible();
	auto starting = wanted && !this->mWanted;
	this->mWanted = wanted;
	// Each time the picture is wanted again, start a fresh session: an old one
	// may wait forever on a frame the compositor dropped (seen after a Mango
	// config reload), leaving a frozen picture. The same goes for a session
	// the compositor ended (window hidden, moved, re-mapped).
	if (wanted && (starting || !this->session) && this->isComponentComplete()) {
		this->restart();
		return;
	}
	if (this->session) this->session->setLive(wanted);
}

void WindowCapture::onStopped() {
	// The compositor ended the session (the window moved workspace, was
	// re-mapped, ...). While the picture is still wanted, try again shortly:
	// a window moved while the overview is open would otherwise stay blank
	// until the next open. Give up after a few tries so a window that can't
	// be captured doesn't spin.
	if (this->session) this->session->deleteLater();
	this->session = nullptr;
	if (!this->mWanted || this->retries >= 6) return;
	this->retries++;
	QTimer::singleShot(250, this, [this] {
		if (this->mWanted && !this->session) this->restart();
	});
}

void WindowCapture::onToplevelAdded(const QString& identifier) {
	if (identifier == this->mIdentifier) this->restart();
}

void WindowCapture::onFrame(const QImage& image) {
	this->pendingImage = image;
	this->imageDirty = true;
	this->retries = 0;
	this->gotFrame = true;

	if (image.size() != this->mSourceSize) {
		this->mSourceSize = image.size();
		emit this->sourceSizeChanged();
	}
	if (!this->mHasContent) {
		this->mHasContent = true;
		emit this->hasContentChanged();
	}
	this->update();
	emit this->frameArrived();
}

QSGNode* WindowCapture::updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData* /*data*/) {
	auto* node = static_cast<QSGSimpleTextureNode*>(oldNode);

	if (this->pendingImage.isNull()) {
		delete node;
		return nullptr;
	}

	if (!node) {
		node = new QSGSimpleTextureNode();
		node->setOwnsTexture(true);
		node->setFiltering(QSGTexture::Linear);
	}

	if (this->imageDirty || !node->texture()) {
		node->setTexture(this->window()->createTextureFromImage(this->pendingImage));
		this->imageDirty = false;
	}

	// Fit, keeping the aspect ratio, centred.
	auto bounds = this->boundingRect();
	auto size = QSizeF(this->pendingImage.size()).scaled(bounds.size(), Qt::KeepAspectRatio);
	node->setRect(QRectF(
	    bounds.x() + (bounds.width() - size.width()) / 2,
	    bounds.y() + (bounds.height() - size.height()) / 2,
	    size.width(),
	    size.height()
	));
	return node;
}
