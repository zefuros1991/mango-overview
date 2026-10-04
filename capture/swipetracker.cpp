#include "swipetracker.hpp"

#include <QEvent>
#include <QNativeGestureEvent>

SwipeTracker::SwipeTracker(QQuickItem* parent): QQuickItem(parent) {}

void SwipeTracker::itemChange(ItemChange change, const ItemChangeData& value) {
	if (change == ItemSceneChange) {
		if (this->mWindow) this->mWindow->removeEventFilter(this);
		this->mWindow = value.window;
		if (this->mWindow) this->mWindow->installEventFilter(this);
	}
	QQuickItem::itemChange(change, value);
}

bool SwipeTracker::eventFilter(QObject* watched, QEvent* event) {
	if (event->type() == QEvent::NativeGesture) {
		auto* ev = static_cast<QNativeGestureEvent*>(event);
		switch (ev->gestureType()) {
		case Qt::BeginNativeGesture: emit this->began(ev->fingerCount()); break;
		case Qt::PanNativeGesture: emit this->moved(ev->delta().x(), ev->delta().y()); break;
		case Qt::EndNativeGesture: emit this->ended(); break;
		default: break;
		}
	}
	return QQuickItem::eventFilter(watched, event);
}
