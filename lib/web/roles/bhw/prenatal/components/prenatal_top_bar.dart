import 'package:flutter/material.dart';
import 'prenatal_constants.dart';

class PrenatalTopBar extends StatelessWidget {
  final VoidCallback onRefresh;

  const PrenatalTopBar({super.key, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border(
          bottom: BorderSide(
            color: primaryAqua.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Logo Icon
          _buildLogoSection(),
          const Spacer(),
          // Search Bar
          _buildSearchBar(),
          const SizedBox(width: 20),
          // Action Buttons
          _buildActionButtons(context),
        ],
      ),
    );
  }

  Widget _buildLogoSection() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryAqua, secondaryIceBlue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: primaryAqua.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.pregnant_woman_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
        const SizedBox(width: 16),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CHO Management System',
              style: TextStyle(
                color: darkDeepTeal,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                letterSpacing: 0.3,
              ),
            ),
            Text(
              'Prenatal Care Module',
              style: TextStyle(
                color: mutedCoolGray,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: lightOffWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: primaryAqua.withValues(alpha: 0.2), width: 1),
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search patient...',
          hintStyle: TextStyle(
            color: mutedCoolGray.withValues(alpha: 0.6),
            fontSize: 13,
          ),
          prefixIcon: Icon(Icons.search, color: mutedCoolGray, size: 18),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        style: TextStyle(
          color: darkDeepTeal,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        // Refresh Button
        _buildActionButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Refresh Data',
          onPressed: onRefresh,
        ),
        const SizedBox(width: 8),
        // Notifications Button
        _buildActionButton(
          icon: Icons.notifications_outlined,
          tooltip: 'Notifications',
          onPressed: () {},
        ),
        const SizedBox(width: 8),
        // Settings Button
        _buildActionButton(
          icon: Icons.settings_outlined,
          tooltip: 'Settings',
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        decoration: BoxDecoration(
          color: mutedCoolGray.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: IconButton(
          icon: Icon(icon, color: mutedCoolGray, size: 20),
          onPressed: onPressed,
          tooltip: tooltip,
        ),
      ),
    );
  }
}
