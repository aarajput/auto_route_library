import 'package:auto_route/src/route/page_route_info.dart';
import 'package:auto_route/src/route/route_data_scope.dart';
import 'package:auto_route/src/router/controller/controller_scope.dart';
import 'package:auto_route/src/router/controller/routing_controller.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../../auto_route.dart';
import '../controller/routing_controller.dart';
import 'auto_route_navigator.dart';

class AutoRouter extends StatefulWidget {
  final NavigatorObserversBuilder navigatorObservers;
  final Widget Function(BuildContext context, Widget content)? builder;
  final String? navRestorationScopeId;
  final bool inheritNavigatorObservers;
  final GlobalKey<NavigatorState>? navigatorKey;

  const AutoRouter({
    Key? key,
    this.navigatorObservers =
        AutoRouterDelegate.defaultNavigatorObserversBuilder,
    this.builder,
    this.navRestorationScopeId,
    this.navigatorKey,
    this.inheritNavigatorObservers = true,
  }) : super(key: key);

  static Widget declarative({
    Key? key,
    NavigatorObserversBuilder navigatorObservers =
        AutoRouterDelegate.defaultNavigatorObserversBuilder,
    required RoutesBuilder routes,
    RoutePopCallBack? onPopRoute,
    String? navRestorationScopeId,
    bool inheritNavigatorObservers = true,
    GlobalKey<NavigatorState>? navigatorKey,
  }) =>
      _DeclarativeAutoRouter(
        onPopRoute: onPopRoute,
        navigatorKey: navigatorKey,
        navRestorationScopeId: navRestorationScopeId,
        navigatorObservers: navigatorObservers,
        routes: routes,
      );

  @override
  AutoRouterState createState() => AutoRouterState();

  static StackRouter of(BuildContext context) {
    var scope = StackRouterScope.of(context);
    assert(() {
      if (scope == null) {
        throw FlutterError(
            'AutoRouter operation requested with a context that does not include an AutoRouter.\n'
            'The context used to retrieve the Router must be that of a widget that '
            'is a descendant of an AutoRouter widget.');
      }
      return true;
    }());
    return scope!.controller;
  }

  static StackRouter? innerRouterOf(BuildContext context, String routeName) {
    return of(context).innerRouterOf<StackRouter>(routeName);
  }
}

class AutoRouterState extends State<AutoRouter> {
  StackRouter? _controller;

  StackRouter? get controller => _controller;
  late List<NavigatorObserver> _navigatorObservers;
  late NavigatorObserversBuilder _inheritableObserversBuilder;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parentData = RouteDataScope.of(context);
    final parentScope = RoutingControllerScope.of(context);
    if (_controller == null) {
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
      _controller = NestedStackRouter(
        parent: parent,
        key: parentData.key,
        routeData: parentData,
        navigatorKey: widget.navigatorKey,
        routeCollection: parent.routeCollection.subCollectionOf(
          parentData.name,
        ),
        pageBuilder: parent.pageBuilder,
        preMatchedRoutes: parentData.preMatchedPendingRoutes,
      );
      parent.attachChildController(_controller!);
      _controller!.addListener(_rebuildListener);
    }
  }

  void _rebuildListener() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(_controller != null);
    var navigator = AutoRouteNavigator(
      router: _controller!,
      navRestorationScopeId: widget.navRestorationScopeId,
      navigatorObservers: _navigatorObservers,
    );
    final segmentsHash = controller!.currentSegmentsHash;
    return RoutingControllerScope(
      controller: _controller!,
      navigatorObservers: _inheritableObserversBuilder,
      segmentsHash: segmentsHash,
      child: StackRouterScope(
        controller: _controller!,
        segmentsHash: segmentsHash,
        child: widget.builder == null
            ? navigator
            : Builder(
                builder: (ctx) => widget.builder!(ctx, navigator),
              ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    _controller?.removeListener(_rebuildListener);
    _controller?.dispose();
    _controller = null;
  }
}

typedef RoutesGenerator = List<PageRouteInfo> Function(
    BuildContext context, List<PageRouteInfo> routes);

class _DeclarativeAutoRouter extends StatefulWidget {
  final RoutesBuilder routes;
  final RoutePopCallBack? onPopRoute;
  final InitialRoutesCallBack? onInitialRoutes;
  final NavigatorObserversBuilder navigatorObservers;
  final String? navRestorationScopeId;
  final bool inheritNavigatorObservers;
  final GlobalKey<NavigatorState>? navigatorKey;

  const _DeclarativeAutoRouter({
    Key? key,
    required this.routes,
    this.navigatorObservers =
        AutoRouterDelegate.defaultNavigatorObserversBuilder,
    this.onPopRoute,
    this.onInitialRoutes,
    this.navigatorKey,
    this.navRestorationScopeId,
    this.inheritNavigatorObservers = true,
  }) : super(key: key);

  @override
  _DeclarativeAutoRouterState createState() => _DeclarativeAutoRouterState();
}

class _DeclarativeAutoRouterState extends State<_DeclarativeAutoRouter> {
  late List<PageRouteInfo> _routes;
  StackRouter? _controller;
  late HeroController _heroController;

  StackRouter? get controller => _controller;
  late List<NavigatorObserver> _navigatorObservers;
  late NavigatorObserversBuilder _inheritableObserversBuilder;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parentData = RouteDataScope.of(context);
    if (_controller == null) {
      _heroController = HeroController();
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
      _controller = NestedStackRouter(
          parent: parent,
          key: parentData.key,
          routeData: parentData,
          stackManagedByWidget: true,
          navigatorKey: widget.navigatorKey,
          routeCollection: parent.routeCollection.subCollectionOf(
            parentData.name,
          ),
          pageBuilder: parent.pageBuilder);
      parent.attachChildController(_controller!);
    }
    _updateRoutes(widget.routes(context));
  }

  void _updateRoutes(List<PageRouteInfo> routes) {
    _routes = routes;
    _controller!.updateDeclarativeRoutes(routes);
  }

  void _rebuildListener() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    super.dispose();
    _controller?.removeListener(_rebuildListener);
    _controller?.dispose();
    _controller = null;
  }

  @override
  Widget build(BuildContext context) {
    assert(_controller != null);
    final segmentsHash = controller!.currentSegmentsHash;
    return RoutingControllerScope(
      controller: _controller!,
      navigatorObservers: _inheritableObserversBuilder,
      segmentsHash: segmentsHash,
      child: HeroControllerScope(
        controller: _heroController,
        child: AutoRouteNavigator(
          router: _controller!,
          navRestorationScopeId: widget.navRestorationScopeId,
          navigatorObservers: _navigatorObservers,
          didPop: widget.onPopRoute,
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _DeclarativeAutoRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    var newRoutes = widget.routes(context);
    if (!ListEquality().equals(newRoutes, _routes)) {
      _updateRoutes(newRoutes);
      WidgetsBinding.instance?.addPostFrameCallback((_) {
        AutoRouterDelegate.of(context).notifyUrlChanged();
      });
    }
  }
}

class EmptyRouterPage extends AutoRouter {
  const EmptyRouterPage({Key? key}) : super(key: key);
}
