#pragma once

#include <QImage>
#include <QPointer>
#include <QQuickItem>
#include <QSize>
#include <QtQml/qqmlregistration.h>

class CaptureSession;

///! Live video of one window.
/// Pick the window by its ext-foreign-toplevel-list identifier
/// (mango: `foreign_toplevel_id` in `mmsg get all-clients`).
/// The picture keeps the window's aspect ratio and is centred in the item.
class WindowCapture: public QQuickItem {
	Q_OBJECT;
	QML_ELEMENT;
	Q_PROPERTY(QString identifier READ identifier WRITE setIdentifier NOTIFY identifierChanged);
	/// Keep updating while visible. When false, one frame is taken and then it holds still.
	Q_PROPERTY(bool live READ live WRITE setLive NOTIFY liveChanged);
	Q_PROPERTY(bool paintCursor READ paintCursor WRITE setPaintCursor NOTIFY paintCursorChanged);
	/// True once the first frame has arrived.
	Q_PROPERTY(bool hasContent READ hasContent NOTIFY hasContentChanged);
	/// Size of the captured window in pixels.
	Q_PROPERTY(QSize sourceSize READ sourceSize NOTIFY sourceSizeChanged);

public:
	explicit WindowCapture(QQuickItem* parent = nullptr);
	~WindowCapture() override;

	[[nodiscard]] QString identifier() const { return this->mIdentifier; }
	void setIdentifier(const QString& identifier);
	[[nodiscard]] bool live() const { return this->mLive; }
	void setLive(bool live);
	[[nodiscard]] bool paintCursor() const { return this->mPaintCursor; }
	void setPaintCursor(bool paintCursor);
	[[nodiscard]] bool hasContent() const { return this->mHasContent; }
	[[nodiscard]] QSize sourceSize() const { return this->mSourceSize; }

	/// Take one new frame (useful when live is false).
	Q_INVOKABLE void captureFrame();

signals:
	void identifierChanged();
	void liveChanged();
	void paintCursorChanged();
	void hasContentChanged();
	void sourceSizeChanged();
	/// A new frame arrived.
	void frameArrived();

protected:
	void componentComplete() override;
	QSGNode* updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData* data) override;
	void itemChange(ItemChange change, const ItemChangeData& value) override;

private slots:
	void onFrame(const QImage& image);
	void onToplevelAdded(const QString& identifier);

private:
	void restart();
	void stop();
	void updateLive();

	QString mIdentifier;
	bool mLive = true;
	bool mPaintCursor = false;
	bool mHasContent = false;
	bool mWanted = false; // live and visible, as of the last updateLive()
	QSize mSourceSize;

	QPointer<CaptureSession> session;
	QImage pendingImage;
	bool imageDirty = false;
};
