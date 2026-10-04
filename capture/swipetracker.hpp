#pragma once

#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtQml/qqmlregistration.h>

///! Touchpad swipes on the window this item is in, finger by finger.
/// The compositor sends swipes to the surface under the pointer
/// (zwp_pointer_gestures_v1); Qt turns them into native gesture events on the
/// window. This reports them live, so the overview can follow the fingers
/// instead of waiting for the gesture to end.
class SwipeTracker: public QQuickItem {
	Q_OBJECT;
	QML_ELEMENT;

public:
	explicit SwipeTracker(QQuickItem* parent = nullptr);

signals:
	/// Fingers went down and started moving.
	void began(int fingers);
	/// The fingers moved by (dx, dy) since the last report, in touchpad units
	/// (about the same as pointer pixels).
	void moved(qreal dx, qreal dy);
	/// The fingers lifted (or the compositor took the gesture back).
	void ended();

protected:
	void itemChange(ItemChange change, const ItemChangeData& value) override;
	bool eventFilter(QObject* watched, QEvent* event) override;

private:
	QPointer<QQuickWindow> mWindow;
};
