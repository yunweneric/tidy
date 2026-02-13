import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';
import 'package:mac_uninstaller/features/apps/data/models/mac_app_model.dart';
import 'package:mac_uninstaller/features/apps/logic/app_bloc.dart';
import 'package:mac_uninstaller/features/apps/logic/app_event.dart';
import 'package:mac_uninstaller/features/apps/logic/app_states.dart';
import 'package:mac_uninstaller/features/apps/presentation/widgets/widgets.dart'
    as app_widgets;
import 'package:mac_uninstaller/features/apps/utils/size_utils.dart';

const int _pageSize = 7;

class ListAppsScreen extends StatefulWidget {
  const ListAppsScreen({super.key});

  @override
  State<ListAppsScreen> createState() => _ListAppsScreenState();
}

class _ListAppsScreenState extends State<ListAppsScreen> {
  String _searchQuery = '';
  int _selectedTab = 0;
  final Set<MacApp> _selectedApps = {};
  int _currentPage = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Row(
        children: [
          app_widgets.AppSidebar(
            currentRoute: 'Applications',
            storageUsed: 342,
            storageTotal: 512,
          ),
          Expanded(child: _buildMainContent(context)),
        ],
      ),
    );
  }

  Widget _buildMainContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        app_widgets.AppListHeader(
          title: 'Application Manager',
          selectedCount: _selectedApps.length,
          searchHint: 'Filter apps...',
          onSearchChanged: (q) => setState(() => _searchQuery = q.trim().toLowerCase()),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 25),
                _buildSummaryCards(context),
                const SizedBox(height: 25),
                _buildTabsAndTable(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCards(BuildContext context) {
    return BlocBuilder<AppsBloc, AppsState>(
      builder: (context, state) {
        int totalApps = 0;
        String totalSize = '0 B';
        if (state is AppsLoaded) {
          totalApps = state.apps.length;
          totalSize = formatAppsTotalSize(state.apps);
        }
        return app_widgets.AppSummaryCards(
          totalApps: totalApps,
          appsSpace: totalSize,
          systemJunk: '1.8 GB',
          unusedCount: '12',
        );
      },
    );
  }

  Widget _buildTabsAndTable(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        app_widgets.AppListToolbar(
          selectedTabIndex: _selectedTab,
          onTabChanged: (i) => setState(() => _selectedTab = i),
          selectedCount: _selectedApps.length,
        ),
        Container(
          decoration: const BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
            border: Border(
              left: BorderSide(color: AppTheme.borderSubtle),
              right: BorderSide(color: AppTheme.borderSubtle),
              bottom: BorderSide(color: AppTheme.borderSubtle),
            ),
          ),
          child: BlocBuilder<AppsBloc, AppsState>(
            builder: (context, state) {
              if (state is AppsLoading) {
                return const SizedBox(
                  height: 520,
                  child: Center(
                    child: CircularProgressIndicator(color: AppTheme.accentBlue),
                  ),
                );
              }
              if (state is AppsError) {
                return SizedBox(
                  height: 200,
                  child: Center(
                    child: Text(
                      state.message,
                      style: AppTheme.bodyPrimary.copyWith(color: AppTheme.accentRed),
                    ),
                  ),
                );
              }
              if (state is! AppsLoaded) {
                return const SizedBox(height: 200);
              }

              final filtered =
                  state.apps
                      .where((a) => a.name.toLowerCase().contains(_searchQuery))
                      .toList();
              final totalPages = (filtered.length / _pageSize).ceil().clamp(1, 999);
              final page = _currentPage.clamp(1, totalPages);
              final start = (page - 1) * _pageSize;
              final end = (start + _pageSize).clamp(0, filtered.length);
              final pageApps =
                  filtered.isEmpty ? <MacApp>[] : filtered.sublist(start, end);
              final totalSize = formatAppsTotalSize(filtered);

              if (page != _currentPage && mounted) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => setState(() => _currentPage = page),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DataTableHeader(
                    columnLabels: const [
                      'APPLICATION',
                      'DEVELOPER',
                      'VERSION',
                      'LAST OPENED',
                      'SIZE',
                    ],
                    flexValues: const [3, 2, 1, 2, 1],
                    showSelectAll: true,
                  ),
                  ...pageApps.map(
                    (app) => app_widgets.AppTableRow(
                      app: app,
                      selected: _selectedApps.contains(app),
                      onSelectionChanged: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedApps.add(app);
                          } else {
                            _selectedApps.remove(app);
                          }
                        });
                      },
                      onUninstall: () => _showUninstallDialog(context, app),
                    ),
                  ),
                  app_widgets.AppTableFooter(
                    itemCount: filtered.length,
                    totalSize: totalSize,
                    currentPage: _currentPage,
                    totalPages: totalPages,
                    onPageChanged: (p) => setState(() => _currentPage = p),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _showUninstallDialog(BuildContext context, MacApp app) {
    app_widgets.UninstallConfirmDialog.show(context, app, () {
      context.read<AppsBloc>().add(UninstallAppEvent(app));
    });
  }
}
