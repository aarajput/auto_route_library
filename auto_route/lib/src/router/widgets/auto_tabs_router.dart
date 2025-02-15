import 'package:auto_route/src/route/page_route_info.dart';
import 'package:auto_route/src/route/route_data_scope.dart';
import 'package:auto_route/src/router/controller/controller_scope.dart';
import 'package:auto_route/src/router/controller/routing_controller.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../../auto_route.dart';
import '../controller/routing_controller.dart';

typedef AnimatedIndexedStackBuilder = Widget Function(
    BuildContext context, Widget child, Animation<double> animation);

class AutoTabsRouter extends StatefulWidget {
  final AnimatedIndexedStackBuilder? builder;
  final List<PageRouteInfo> routes;
  final Duration duration;
  final Curve curve;
  final bool lazyLoad;
  final NavigatorObserversBuilder navigatorObservers;
  final bool inheritNavigatorObservers;
  final int? activeIndex;
  const AutoTabsRouter({
    Key? key,
    required this.routes,
    this.lazyLoad = true,
    this.activeIndex,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.ease,
    this.builder,
    this.inheritNavigatorObservers = true,
    this.navigatorObservers =
        AutoRouterDelegate.defaultNavigatorObserversBuilder,
  }) : super(key: key);

  @override
  AutoTabsRouterState createState() => AutoTabsRouterState();

  static TabsRouter of(BuildContext context) {
    var scope = TabsRouterScope.of(context);
    assert(() {
      if (scope == null) {
        throw FlutterError(
            'AutoTabsRouter operation requested with a context that does not include an AutoTabsRouter.\n'
            'The context used to retrieve the AutoTabsRouter must be that of a widget that '
            'is a descendant of an AutoTabsRouter widget.');
      }
      return true;
    }());
    return scope!.controller;
  }
}

class AutoTabsRouterState extends State<AutoTabsRouter>
    with SingleTickerProviderStateMixin {
  TabsRouter? _controller;
  late AnimationController _animationController;
  late Animation<double> _animation;
  int _index = 0;

  TabsRouter? get controller => _controller;

  @override
  void initState() {
    _animationController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: widget.curve,
      ),
    );
    super.initState();
  }

  late List<NavigatorObserver> _navigatorObservers;
  late NavigatorObserversBuilder _inheritableObserversBuilder;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parentRoute = RouteDataScope.of(context);
    if (_controller == null) {
      final parentScope = RoutingControllerScope.of(context);
      assert(parentScope != null);
      _inheritableObserversBuilder = () {
        var observers = widget.navigatorObservers();
        if (!widget.inheritNavigatorObservers) {
          return observers;
        }
        var inheritedObservers = parentScope!.navigatorObservers();
        return inheritedObservers + observers;
      };
      _navigatorObservers = _inheritableObserversBuilder();
      final parent = parentScope!.controller;
      _controller = TabsRouter(
          parent: parent,
          key: parentRoute.key,
          initialIndex: widget.activeIndex,
          routeData: parentRoute,
          routeCollection: parent.routeCollection.subCollectionOf(
            parentRoute.name,
          ),
          pageBuilder: parent.pageBuilder,
          preMatchedRoutes: parentRoute.preMatchedPendingRoutes);
      parent.attachChildController(_controller!);
      _resetController();
    }
  }

  void _resetController() {
    assert(_controller != null);
    _controller!.setupRoutes(widget.routes);
    _index = _controller!.activeIndex;
    _animationController.value = 1.0;
    _controller!.addListener(() {
      if (widget.activeIndex == null && _controller!.activeIndex != _index) {
        setState(() {
          _index = _controller!.activeIndex;
        });
        _animationController.forward(from: 0.0);
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    _animationController.dispose();
    _controller?.dispose();
    _controller = null;
  }

  @override
  void didUpdateWidget(covariant AutoTabsRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!ListEquality().equals(widget.routes, oldWidget.routes)) {
      _resetController();
    }
    if (widget.activeIndex != null &&
        widget.activeIndex != oldWidget.activeIndex) {
      _animationController.value = 1.0;
      _index = widget.activeIndex!;
      _animationController.forward(from: 0.0);
      _controller!.setActiveIndex(_index, notify: false);
      WidgetsBinding.instance?.addPostFrameCallback((_) {
        AutoRouterDelegate.of(context).notifyUrlChanged();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(_controller != null);
    final stack = _controller!.stack;
    final builder = widget.builder ?? _defaultBuilder;

    final builderChild = stack.isEmpty
        ? Container(color: Theme.of(context).scaffoldBackgroundColor)
        : _IndexedStackBuilder(
            activeIndex: _index,
            lazyLoad: widget.lazyLoad,
            navigatorObservers: _navigatorObservers,
            itemBuilder: (BuildContext context, int index) {
              return stack[index].buildPage(context);
            },
            stack: stack,
          );
    var segmentsHash = controller!.currentSegmentsHash;
    return RoutingControllerScope(
      controller: _controller!,
      navigatorObservers: _inheritableObserversBuilder,
      segmentsHash: segmentsHash,
      child: TabsRouterScope(
          controller: _controller!,
          segmentsHash: segmentsHash,
          child: AnimatedBuilder(
            animation: _animation,
            builder: (context, child) =>
                builder(context, child ?? builderChild, _animation),
            child: builderChild,
          )),
    );
  }

  Widget _defaultBuilder(_, child, animation) {
    return FadeTransition(opacity: animation, child: child);
  }
}

class _IndexedStackBuilder extends StatefulWidget {
  final int activeIndex;
  final IndexedWidgetBuilder itemBuilder;
  final bool lazyLoad;
  final List<AutoRoutePage> stack;
  final List<NavigatorObserver> navigatorObservers;

  const _IndexedStackBuilder({
    Key? key,
    required this.activeIndex,
    required this.itemBuilder,
    required this.navigatorObservers,
    required this.stack,
    required this.lazyLoad,
  }) : super(key: key);

  @override
  _IndexedStackBuilderState createState() => _IndexedStackBuilderState();
}

class _DummyWidget extends SizedBox {
  const _DummyWidget() : super(width: 0.0, height: 0.0);
}

class _IndexedStackBuilderState extends State<_IndexedStackBuilder> {
  final _dummyWidget = const _DummyWidget();
  final _pages = <Widget>[];

  void _didInitTabRoute(int index, [int previous = -1]) {
    widget.navigatorObservers
        .whereType<AutoRouterObserver>()
        .forEach((observer) {
      final routes = widget.stack.map((e) => e.routeData.route).toList();
      var previousRoute;
      if (previous != -1) {
        previousRoute =
            TabPageRoute(routeInfo: routes[previous], index: previous);
      }
      observer.didInitTabRoute(
        TabPageRoute(routeInfo: routes[index], index: index),
        previousRoute,
      );
    });
  }

  void _didChangeTabRoute(int index, int previous) {
    widget.navigatorObservers
        .whereType<AutoRouterObserver>()
        .forEach((observer) {
      final routes = widget.stack.map((e) => e.routeData.route).toList();
      observer.didChangeTabRoute(
        TabPageRoute(routeInfo: routes[index], index: index),
        TabPageRoute(routeInfo: routes[previous], index: previous),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.stack.length; ++i) {
      if (i == widget.activeIndex || !widget.lazyLoad) {
        _pages.add(widget.itemBuilder(context, i));
        _didInitTabRoute(i);
      } else {
        _pages.add(_dummyWidget);
      }
    }
  }

  @override
  void didUpdateWidget(_IndexedStackBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lazyLoad && _pages[widget.activeIndex] is _DummyWidget) {
      _didInitTabRoute(widget.activeIndex, oldWidget.activeIndex);
      _pages[widget.activeIndex] =
          widget.itemBuilder(context, widget.activeIndex);
    } else if (widget.activeIndex != oldWidget.activeIndex) {
      _didChangeTabRoute(widget.activeIndex, oldWidget.activeIndex);
    }
  }

  @override
  Widget build(BuildContext context) => IndexedStack(
        index: widget.activeIndex,
        sizing: StackFit.expand,
        children: _pages,
      );
}
