import 'package:flutter/material.dart';

class WidgetSizeProxy {
  double deltaHeight = 0.0;
}

class RetainedPositionScrollPhysics extends ScrollPhysics {
  const RetainedPositionScrollPhysics({
    super.parent,
    required this.widgetSizeProxy,
  });

  final WidgetSizeProxy widgetSizeProxy;

  @override
  ScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return RetainedPositionScrollPhysics(
      parent: ancestor,
      widgetSizeProxy: widgetSizeProxy,
    );
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final adjustPosition = super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
    final deltaHeight = widgetSizeProxy.deltaHeight;

    if (isScrolling || velocity.abs() > 0.1) {
      widgetSizeProxy.deltaHeight = 0.0;
      return adjustPosition;
    }

    if (deltaHeight.abs() < 0.5) {
      return adjustPosition;
    }

    widgetSizeProxy.deltaHeight = 0.0;

    if (adjustPosition <= 44) {
      // 44 is just a threshold to adjust the position when the user scrolls to the bottom
      // if the user scrolls to the bottom, the adjustPosition is 0
      // so we need to return the original position
      return adjustPosition;
    } else {
      // Add the delta height to keep the scroll position stable
      return adjustPosition + deltaHeight;
    }
  }
}
