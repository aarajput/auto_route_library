import 'package:auto_route/auto_route.dart';
import 'package:auto_route/src/matcher/route_matcher.dart';
import 'package:auto_route/src/navigation_failure.dart';
import 'package:auto_route/src/route/page_route_info.dart';
import 'package:auto_route/src/route/route_config.dart';
import 'package:auto_route/src/route/route_data_scope.dart';
import 'package:auto_route/src/router/auto_route_page.dart';
import 'package:collection/collection.dart' show ListEquality;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../utils.dart';

part '../../route/route_data.dart';

typedef RouteDataPredicate = bool Function(RouteData route);

abstract class RoutingController with ChangeNotifier {
  final Map<ValueKey<String>, RoutingController> _childControllers = {};
  final List<AutoRoutePage> _pages = [];

  void attachChildController(RoutingController childController) {
    _childControllers[childController.key] = childController;
  }

  void removeChildController(RoutingController childController) {
    _childControllers.remove(childController.key);
  }

  RoutingController? getChildRouter(ValueKey<String> key) {
    return _childControllers[key];
  }

  List<RouteData> get stackData =>
      List.unmodifiable(_pages.map((e) => e.routeData));

  bool isRouteActive(String routeName) {
    return root._isRouteActive(routeName);
  }

  bool _isRouteActive(String routeName) {
    return currentSegments.any(
      (r) => r.routeName == routeName,
    );
  }

  bool isPathActive(String path) {
    return root._isPathActive(path);
  }

  bool _isPathActive(String pattern) {
    return RegExp(pattern)
        .hasMatch(p.joinAll(currentSegments.map((e) => e.stringMatch)));
  }

  bool _canHandleNavigation(PageRouteInfo route) {
    return routeCollection.containsKey(route.routeName);
  }

  List<RoutingController> _getAncestors() {
    void collectRouters(
        RoutingController currentParent, List<RoutingController> all) {
      all.add(currentParent);
      if (currentParent._parent != null) {
        collectRouters(currentParent._parent!, all);
      }
    }

    final routers = <RoutingController>[];
    if (_parent != null) {
      collectRouters(_parent!, routers);
    }
    return routers;
  }

  // should find a way to avoid this
  void _updateSharedPathData(Map<String, dynamic> queryParams, String fragment,
      {bool includeAncestors = false}) {
    _pages.forEach(
      (p) {
        p.routeData._route = p.routeData._route.copyWith(
          queryParams: queryParams,
          fragment: fragment,
        );
      },
    );
    if (_parent != null) {
      _parent!._updateSharedPathData(queryParams, fragment);
    }
  }

  int get currentSegmentsHash => const ListEquality().hash(currentSegments);

  ValueKey<String> get key;

  RouteMatcher get matcher;

  List<AutoRoutePage> get stack;

  RoutingController? get _parent;

  T? parent<T extends RoutingController>() {
    return _parent == null ? null : _parent as T;
  }

  StackRouter get root => (_parent?.root ?? this) as StackRouter;

  StackRouter? get parentAsStackRouter => parent<StackRouter>();

  bool get isRoot => _parent == null;

  RoutingController get topMost;

  RouteData? get currentChild;

  RouteData get current;

  RouteData get topRoute => topMost.current;

  RouteData get routeData;

  RouteCollection get routeCollection;

  bool get hasEntries;

  T? innerRouterOf<T extends RoutingController>(String routeName) {
    if (_childControllers.isEmpty) {
      return null;
    }
    return _childControllers.values.whereType<T>().lastOrNull(
          ((c) => c.routeData.name == routeName),
        );
  }

  List<PageRouteInfo>? get preMatchedRoutes;

  PageBuilder get pageBuilder;

  @optionalTypeArgs
  Future<bool> pop<T extends Object?>([T? result]);

  @optionalTypeArgs
  Future<bool> popTop<T extends Object?>([T? result]) => topMost.pop<T>(result);

  bool get canPopSelfOrChildren;

  List<PageRouteInfo> get currentSegments;

  @override
  String toString() => '${routeData.name} Router';

  Future<void> navigateAll(List<PageRouteInfo> routes,
      {OnNavigationFailure? onFailure});
}

class TabsRouter extends RoutingController {
  final RoutingController? _parent;
  final ValueKey<String> key;
  final RouteCollection routeCollection;
  final PageBuilder pageBuilder;
  final RouteMatcher matcher;
  final RouteData routeData;
  final List<PageRouteInfo>? preMatchedRoutes;
  int _activeIndex = 0;

  TabsRouter(
      {required this.routeCollection,
      required this.pageBuilder,
      required this.key,
      required this.routeData,
      RoutingController? parent,
      this.preMatchedRoutes,
      int? initialIndex})
      : matcher = RouteMatcher(routeCollection),
        _activeIndex = initialIndex ?? 0,
        _parent = parent {
    if (parent != null) {
      addListener(root.notifyListeners);
    }
  }

  RouteData get current {
    return currentChild ?? routeData;
  }

  RouteData? get currentChild {
    if (_activeIndex < _pages.length) {
      return _pages[_activeIndex].routeData;
    } else {
      return null;
    }
  }

  int get activeIndex => _activeIndex;

  void setActiveIndex(int index, {bool notify = true}) {
    assert(index >= 0 && index < _pages.length);
    if (_activeIndex != index) {
      _activeIndex = index;
      if (notify) {
        notifyListeners();
      }
    }
  }

  @override
  List<AutoRoutePage> get stack => List.unmodifiable(_pages);

  AutoRoutePage? get _activePage {
    return _pages.isEmpty ? null : _pages[_activeIndex];
  }

  @override
  RoutingController get topMost {
    var activeKey = _activePage?.routeData.key;
    if (_childControllers.containsKey(activeKey)) {
      return _childControllers[activeKey]!.topMost;
    }
    return this;
  }

  @override
  bool get hasEntries => _pages.isNotEmpty;

  @override
  @optionalTypeArgs
  Future<bool> pop<T extends Object?>([T? result]) {
    if (_parent != null) {
      return _parent!.pop<T>(result);
    } else {
      return SynchronousFuture<bool>(false);
    }
  }

  int _findStackRouterIndexFor(PageRouteInfo route) {
    for (var i = 0; i < _pages.length; i++) {
      var childController = _childControllers[_pages[i].routeData.key];
      if (childController is StackRouter &&
          childController._canHandleNavigation(route)) {
        return i;
      }
    }
    throw FlutterError(
        'Can not find a child controller to handle ${route.routeName}');
  }

  Future<void> pushToChild(PageRouteInfo route,
      {OnNavigationFailure? onFailure}) {
    var scopeIndex = _findStackRouterIndexFor(route);
    setActiveIndex(scopeIndex);
    return stackRouterOfIndex(scopeIndex)!.push(route, onFailure: onFailure);
  }

  Future<void> replaceInChild(PageRouteInfo route,
      {OnNavigationFailure? onFailure}) {
    var scopeIndex = _findStackRouterIndexFor(route);
    setActiveIndex(scopeIndex);
    return stackRouterOfIndex(scopeIndex)!.replace(route, onFailure: onFailure);
  }

  void setupRoutes(List<PageRouteInfo> routes) {
    final routesToPush = List.of(routes);
    if (preMatchedRoutes?.isNotEmpty == true) {
      final preMatchedRoute = preMatchedRoutes!.last;
      final correspondingRouteIndex = routes.indexWhere(
        (r) => r.routeName == preMatchedRoute.routeName,
      );
      if (correspondingRouteIndex != -1) {
        routesToPush
          ..removeAt(correspondingRouteIndex)
          ..insert(correspondingRouteIndex, preMatchedRoute);
        _activeIndex = correspondingRouteIndex;
      }
    }
    if (routesToPush.isNotEmpty) {
      _pushAll(routesToPush);
    }
  }

  void _pushAll(List<PageRouteInfo> routes) {
    _pages.clear();
    for (var route in routes) {
      var data = _getRouteData(route);
      _pages.add(pageBuilder(data));
    }
  }

  RouteData _getRouteData(PageRouteInfo route) {
    final config = matcher.resolveConfigOrNull(route);
    if (config == null) {
      throw FlutterError("$this can not navigate to ${route.routeName}");
    } else {
      if (config.guards.isNotEmpty == true) {
        throw FlutterError("Tab routes can not have guards");
      }
      final data = _createRouteData(route, config, routeData);
      return data;
    }
  }

  @override
  Future<void> navigateAll(List<PageRouteInfo> routes,
      {OnNavigationFailure? onFailure}) async {
    if (routes.isNotEmpty) {
      final preMatchedRoute = routes.last;
      final mayUpdateKey = ValueKey<String>(preMatchedRoute.stringMatch);
      final pageToUpdateIndex = _pages.indexWhere(
        (p) => p.routeData.key == mayUpdateKey,
      );

      if (pageToUpdateIndex != -1) {
        setActiveIndex(pageToUpdateIndex);
        var mayUpdateController = _childControllers[mayUpdateKey];
        if (preMatchedRoute.hasChildren) {
          if (mayUpdateController != null) {
            await mayUpdateController.navigateAll(preMatchedRoute.children!,
                onFailure: onFailure);
          } else {
            final data = _getRouteData(preMatchedRoute);
            _pages
              ..removeAt(pageToUpdateIndex)
              ..insert(pageToUpdateIndex, pageBuilder(data));
          }
        }
      }
      _updateSharedPathData(
        preMatchedRoute.queryParams,
        preMatchedRoute.fragment,
        includeAncestors: false,
      );
    }

    return SynchronousFuture(null);
  }

  StackRouter? stackRouterOfIndex(int index) {
    if (_childControllers.isEmpty) {
      return null;
    }
    final routeKey = _pages[index].routeData.key;
    if (_childControllers[routeKey] is StackRouter) {
      return _childControllers[routeKey] as StackRouter;
    } else {
      return null;
    }
  }

  @override
  bool get canPopSelfOrChildren {
    if (_childControllers[_pages[_activeIndex].key] != null) {
      return _childControllers[_pages[_activeIndex].key]!.canPopSelfOrChildren;
    }
    return false;
  }

  @override
  List<PageRouteInfo> get currentSegments {
    var currentData = currentChild;
    final segments = <PageRouteInfo>[];
    if (currentData != null) {
      segments.add(currentData.route);
      if (_childControllers.containsKey(currentData.key)) {
        segments.addAll(
          _childControllers[currentData.key]!.currentSegments,
        );
      }
    } else if (routeData.route.hasChildren) {
      segments.addAll(
        routeData.route.children!.last.flattened,
      );
    }
    return segments;
  }
}

abstract class StackRouter extends RoutingController {
  final RoutingController? _parent;
  final ValueKey<String> key;
  final GlobalKey<NavigatorState> _navigatorKey;
  final List<PageRouteInfo>? preMatchedRoutes;

  @override
  final RouteData routeData;

  StackRouter({
    required this.key,
    RoutingController? parent,
    GlobalKey<NavigatorState>? navigatorKey,
    required this.routeData,
    this.preMatchedRoutes,
  })  : _navigatorKey = navigatorKey ?? GlobalKey<NavigatorState>(),
        _parent = parent {
    if (parent != null) {
      addListener(root.notifyListeners);
    }
  }

  GlobalKey<NavigatorState> get navigatorKey => _navigatorKey;

  RouteCollection get routeCollection;

  PageBuilder get pageBuilder;

  RouteMatcher get matcher;

  bool get stackManagedByWidget;

  void _pushInitialRoutes() {
    if (!stackManagedByWidget && preMatchedRoutes?.isNotEmpty == true) {
      pushAll(preMatchedRoutes!);
    }
  }

  @override
  List<PageRouteInfo> get currentSegments {
    var currentData = currentChild;
    final segments = <PageRouteInfo>[];
    if (currentData != null) {
      segments.add(currentData.route);
      if (_childControllers.containsKey(currentData.key)) {
        segments.addAll(
          _childControllers[currentData.key]!.currentSegments,
        );
      }
    } else if (routeData.route.hasChildren) {
      segments.addAll(
        routeData.route.children!.last.flattened,
      );
    }
    return segments;
  }

  @override
  bool get canPopSelfOrChildren {
    if (_pages.length > 1) {
      return true;
    } else if (_pages.isNotEmpty &&
        _childControllers[_pages.last.key] != null) {
      return _childControllers[_pages.last.key]!.canPopSelfOrChildren;
    }
    return false;
  }

  @override
  RouteData get current {
    return currentChild ?? routeData;
  }

  @override
  RouteData? get currentChild {
    if (_pages.isNotEmpty) {
      return _pages.last.routeData;
    }
    return null;
  }

  @override
  RoutingController get topMost {
    if (_childControllers.isNotEmpty) {
      var topRouteKey = _pages.last.routeData.key;
      if (_childControllers.containsKey(topRouteKey)) {
        return _childControllers[topRouteKey]!.topMost;
      }
    }
    return this;
  }

  @override
  @optionalTypeArgs
  Future<bool> pop<T extends Object?>([T? result]) async {
    final NavigatorState? navigator = _navigatorKey.currentState;
    if (navigator == null) return SynchronousFuture<bool>(false);
    if (await navigator.maybePop<T>(result)) {
      return true;
    } else if (_parent != null) {
      return _parent!.pop<T>(result);
    } else {
      return false;
    }
  }

  bool removeLast() => _removeLast();

  void removeRoute(RouteData route, {bool notify = true}) {
    _pages.removeWhere((p) => p.routeData.key == route.key);
    if (_childControllers.containsKey(route.key)) {
      _childControllers.remove(route.key);
    }
    if (notify) {
      notifyListeners();
    }
  }

  bool _removeLast({bool notify = true}) {
    var didRemove = false;
    if (_pages.isNotEmpty) {
      removeRoute(_pages.last.routeData);
      if (notify) {
        notifyListeners();
      }
      didRemove = true;
    }
    return didRemove;
  }

  @override
  List<AutoRoutePage> get stack => List.unmodifiable(_pages);

  @optionalTypeArgs
  Future<T?> push<T extends Object?>(PageRouteInfo route,
      {OnNavigationFailure? onFailure}) async {
    return _findStackScope(route)._push<T>(route, onFailure: onFailure);
  }

  StackRouter _findStackScope(PageRouteInfo route) {
    if (_parent == null || _canHandleNavigation(route)) {
      return this;
    }
    final stackRouters = _getAncestors().whereType<StackRouter>();
    return stackRouters.firstWhere((c) => c._canHandleNavigation(route),
        orElse: () => this);
  }

  RoutingController _findScope<T extends RoutingController>(
      PageRouteInfo route) {
    if (_parent == null || _canHandleNavigation(route)) {
      return this;
    }
    final routers = [this, ..._getAncestors()];
    return routers.firstWhere((r) => r._canHandleNavigation(route),
        orElse: () => this);
  }

  _StackRouterScopeResult? _findPathScopeOrReportFailure(String path,
      {bool includePrefixMatches = false, OnNavigationFailure? onFailure}) {
    final stackRouters = [this, ..._getAncestors().whereType<StackRouter>()];
    for (var router in stackRouters) {
      final matches = router.matcher.match(
        path,
        includePrefixMatches: includePrefixMatches,
      );
      if (matches != null) {
        return _StackRouterScopeResult(router, matches);
      }
    }
    if (onFailure != null) {
      onFailure(
        RouteNotFoundFailure(
          PageRouteInfo('', path: path),
        ),
      );
    } else {
      throw FlutterError('Can not navigate to $path');
    }
    return null;
  }

  Future<dynamic> _navigateAll(List<PageRouteInfo> routes,
      {OnNavigationFailure? onFailure}) async {
    final anchor = routes.first;
    final anchorPage = _pages.lastOrNull(
      (p) => p.key == ValueKey(anchor.stringMatch),
    );
    if (anchorPage != null) {
      for (var candidate in List.unmodifiable(_pages).reversed) {
        _pages.removeLast();
        if (candidate.key == anchorPage.key) {
          break;
        } else {
          if (_childControllers.containsKey(candidate.key)) {
            _childControllers.remove(candidate.key);
          }
        }
      }
    }
    _pushAllGuarded(
      routes,
      onFailure: onFailure,
      notify: true,
      updateAncestorsPathData: false,
    );
    return SynchronousFuture(null);
  }

  Future<dynamic> navigate(PageRouteInfo route,
      {OnNavigationFailure? onFailure}) async {
    return _findScope(route).navigateAll([route], onFailure: onFailure);
  }

  @optionalTypeArgs
  Future<T?> _push<T extends Object?>(PageRouteInfo route,
      {OnNavigationFailure? onFailure, bool notify = true}) async {
    assert(
      !stackManagedByWidget,
      'Pages stack can be managed by either the Widget (AutoRouter.declarative) or the (StackRouter)',
    );
    var config = _resolveConfigOrReportFailure(route, onFailure);
    if (config == null) {
      return null;
    }
    if (await _canNavigate([route], config, onFailure)) {
      _updateSharedPathData(
        route.queryParams,
        route.fragment,
        includeAncestors: true,
      );
      return _addEntry<T>(route, config: config, notify: notify);
    }
    return null;
  }

  @optionalTypeArgs
  Future<T?> replace<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) {
    assert(_pages.isNotEmpty);
    removeLast();
    return push<T>(route, onFailure: onFailure);
  }

  Future<void> pushAll(
    List<PageRouteInfo> routes, {
    OnNavigationFailure? onFailure,
  }) {
    assert(routes.isNotEmpty);
    return _findStackScope(routes.first)._pushAll(
      routes,
      onFailure: onFailure,
      notify: true,
    );
  }

  Future<void> popAndPushAll(List<PageRouteInfo> routes, {onFailure}) {
    pop();
    return _pushAll(routes, onFailure: onFailure);
  }

  Future<void> replaceAll(
    List<PageRouteInfo> routes, {
    OnNavigationFailure? onFailure,
  }) {
    _clearHistory();
    return _pushAll(routes, onFailure: onFailure);
  }

  void popUntilRoot() {
    assert(_navigatorKey.currentState != null);
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  @optionalTypeArgs
  Future<T?> popAndPush<T extends Object?, TO extends Object?>(
    PageRouteInfo route, {
    TO? result,
    OnNavigationFailure? onFailure,
  }) {
    pop<TO>(result);
    return push<T>(route, onFailure: onFailure);
  }

  bool removeUntil(RouteDataPredicate predicate) => _removeUntil(predicate);

  void popUntil(RoutePredicate predicate) {
    _navigatorKey.currentState?.popUntil(predicate);
  }

  bool _removeUntil(RouteDataPredicate predicate, {bool notify = true}) {
    var didRemove = false;
    for (var candidate in List.unmodifiable(_pages).reversed) {
      if (predicate(candidate.routeData)) {
        break;
      } else {
        _removeLast(notify: false);
        didRemove = true;
      }
    }
    if (didRemove && notify) {
      notifyListeners();
    }
    return didRemove;
  }

  bool removeWhere(RouteDataPredicate predicate) {
    var didRemove = false;
    for (var entry in List.unmodifiable(_pages)) {
      if (predicate(entry.routeData)) {
        didRemove = true;
        _pages.remove(entry);
      }
    }
    notifyListeners();
    return didRemove;
  }

  void updateDeclarativeRoutes(List<PageRouteInfo> routes) {
    _clearHistory();
    for (var route in routes) {
      var config = _resolveConfigOrReportFailure(route);
      if (config == null) {
        break;
      }
      if (!listNullOrEmpty(config.guards)) {
        throw FlutterError("Declarative routes can not have guards");
      }
      final data = _createRouteData(route, config, routeData);
      _pages.add(pageBuilder(data));
    }
  }

  Future<void> _pushAll(
    List<PageRouteInfo> routes, {
    OnNavigationFailure? onFailure,
    bool notify = true,
  }) async {
    _pushAllGuarded(routes, onFailure: onFailure, notify: notify);
    return SynchronousFuture(null);
  }

  @optionalTypeArgs
  Future<T?> _pushAllGuarded<T extends Object?>(List<PageRouteInfo> routes,
      {OnNavigationFailure? onFailure,
      bool notify = true,
      bool updateAncestorsPathData = true}) async {
    assert(
      !stackManagedByWidget,
      'Pages stack can be managed by either the Widget (AutoRouter.declarative) or the (StackRouter)',
    );

    final checkedRoutes = List<PageRouteInfo>.from(routes);
    for (var i = 0; i < routes.length; i++) {
      var route = routes[i];
      var config = _resolveConfigOrReportFailure(route, onFailure);
      if (config == null) {
        break;
      }
      if (await _canNavigate(checkedRoutes, config, onFailure)) {
        checkedRoutes.remove(route);
        if (i != routes.length - 1) {
          _addEntry(route, config: config, notify: false);
        } else {
          _updateSharedPathData(
            route.queryParams,
            route.fragment,
            includeAncestors: updateAncestorsPathData,
          );
          return _addEntry<T>(route, config: config, notify: true);
        }
      } else {
        break;
      }
    }
    if (notify) {
      notifyListeners();
    }
    return SynchronousFuture(null);
  }

  RouteConfig? _resolveConfigOrReportFailure(
    PageRouteInfo route, [
    OnNavigationFailure? onFailure,
  ]) {
    var config = matcher.resolveConfigOrNull(route);
    if (config != null) {
      return config;
    } else {
      if (onFailure != null) {
        onFailure(RouteNotFoundFailure(route));
        return null;
      } else {
        throw FlutterError(
            "[${toString()}] Router can not navigate to ${route.fullPath}");
      }
    }
  }

  Future<T?> _addEntry<T extends Object?>(
    PageRouteInfo route, {
    required RouteConfig config,
    bool notify = true,
  }) {
    final data = _createRouteData(route, config, routeData);
    final page = pageBuilder(data);
    _pages.add(page);
    if (notify) {
      notifyListeners();
    }
    return (page as AutoRoutePage<T>).popped;
  }

  Future<bool> _canNavigate(
    List<PageRouteInfo> routes,
    RouteConfig config,
    OnNavigationFailure? onFailure,
  ) async {
    if (config.guards.isEmpty) {
      return true;
    }
    for (var guard in config.guards) {
      if (!await guard.canNavigate(routes, this)) {
        if (onFailure != null) {
          onFailure(RejectedByGuardFailure(routes, guard));
        }
        return false;
      }
    }
    return true;
  }

  @override
  Future<void> navigateAll(List<PageRouteInfo> routes,
      {OnNavigationFailure? onFailure}) async {
    if (routes.isNotEmpty) {
      final mayUpdateRoute = routes.last;
      final mayUpdateKey = ValueKey<String>(mayUpdateRoute.stringMatch);
      final mayUpdateController = _childControllers[mayUpdateKey];
      if (mayUpdateController != null) {
        if (!(mayUpdateController is StackRouter &&
            mayUpdateController.stackManagedByWidget)) {
          await mayUpdateController.navigateAll(
            mayUpdateRoute.children ?? const <PageRouteInfo>[],
            onFailure: onFailure,
          );
        }
      }
      return _navigateAll(routes, onFailure: onFailure);
    }
    _clearHistory();
    return SynchronousFuture(null);
  }

  void _clearHistory() {
    _pages.clear();
  }

  @Deprecated('Use pushAndPopUntil')
  Future<T?> pushAndRemoveUntil<T extends Object?>(
    PageRouteInfo route, {
    required RoutePredicate predicate,
    OnNavigationFailure? onFailure,
  }) {
    return pushAndPopUntil<T>(
      route,
      predicate: predicate,
      onFailure: onFailure,
    );
  }

  @optionalTypeArgs
  Future<T?> pushAndPopUntil<T extends Object?>(
    PageRouteInfo route, {
    required RoutePredicate predicate,
    OnNavigationFailure? onFailure,
  }) {
    popUntil(predicate);
    return push<T>(route, onFailure: onFailure);
  }

  @optionalTypeArgs
  Future<T?> replaceNamed<T extends Object?>(
    String path, {
    bool includePrefixMatches = false,
    OnNavigationFailure? onFailure,
  }) {
    removeLast();
    return pushNamed<T>(
      path,
      includePrefixMatches: includePrefixMatches,
      onFailure: onFailure,
    );
  }

  Future<void> navigateNamed(
    String path, {
    bool includePrefixMatches = false,
    OnNavigationFailure? onFailure,
  }) {
    final scope = _findPathScopeOrReportFailure(
      path,
      includePrefixMatches: includePrefixMatches,
      onFailure: onFailure,
    );
    if (scope != null) {
      return scope.router.navigateAll(
        List.unmodifiable(
          scope.matches.map((e) => PageRouteInfo.fromMatch(e)),
        ),
      );
    }
    return SynchronousFuture(null);
  }

  @optionalTypeArgs
  Future<T?> pushNamed<T extends Object?>(
    String path, {
    bool includePrefixMatches = false,
    OnNavigationFailure? onFailure,
  }) {
    final scope = _findPathScopeOrReportFailure(
      path,
      includePrefixMatches: includePrefixMatches,
      onFailure: onFailure,
    );
    if (scope != null) {
      return scope.router._pushAllGuarded(
        scope.matches.map((e) => PageRouteInfo.fromMatch(e)).toList(),
        onFailure: onFailure,
      );
    }
    return SynchronousFuture(null);
  }

  @Deprecated('use pushNamed instead')
  @optionalTypeArgs
  Future<T?> pushPath<T extends Object?>(
    String path, {
    bool includePrefixMatches = false,
    OnNavigationFailure? onFailure,
  }) {
    return pushNamed<T>(
      path,
      includePrefixMatches: includePrefixMatches,
      onFailure: onFailure,
    );
  }

  void popUntilRouteWithName(String name) {
    popUntil(ModalRoute.withName(name));
  }

  @override
  bool get hasEntries => _pages.isNotEmpty;
}

RouteData _createRouteData(
    PageRouteInfo route, RouteConfig config, RouteData parent) {
  var routeToPush = route;
  if (config.isSubTree && !route.hasChildren) {
    var matches = RouteMatcher(config.children!).match('');
    if (matches != null) {
      routeToPush = route.copyWith(
        children: matches.map((m) => PageRouteInfo.fromMatch(m)).toList(),
      );
    }
  }
  var activeSegments = <PageRouteInfo>[];
  if (routeToPush.children?.isNotEmpty == true) {
    activeSegments.add(routeToPush.children!.last);
  }
  return RouteData(
    route: routeToPush,
    parent: parent,
    config: config,
    key: ValueKey(routeToPush.stringMatch),
    preMatchedPendingRoutes: routeToPush.children,
  );
}

class NestedStackRouter extends StackRouter {
  final RouteMatcher matcher;
  final RouteCollection routeCollection;
  final PageBuilder pageBuilder;
  final bool stackManagedByWidget;

  NestedStackRouter({
    required this.routeCollection,
    required this.pageBuilder,
    required ValueKey<String> key,
    required RouteData routeData,
    this.stackManagedByWidget = false,
    required RoutingController parent,
    List<PageRouteInfo>? preMatchedRoutes,
    GlobalKey<NavigatorState>? navigatorKey,
  })  : matcher = RouteMatcher(routeCollection),
        super(
          key: key,
          routeData: routeData,
          preMatchedRoutes: preMatchedRoutes,
          parent: parent,
          navigatorKey: navigatorKey,
        ) {
    _pushInitialRoutes();
  }
}

class _StackRouterScopeResult {
  final StackRouter router;
  final List<RouteMatch> matches;

  const _StackRouterScopeResult(this.router, this.matches);
}
