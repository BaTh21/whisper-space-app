import 'package:flutter/material.dart';

enum ButtonVariant { primary, secondary, outlined, text }

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final bool fullWidth;
  final IconData? icon;
  final ButtonVariant variant;
  final bool isLoading;
  
  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.fullWidth = false,
    this.icon,
    this.variant = ButtonVariant.primary,
    this.isLoading = false,
  });
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    Color backgroundColor;
    Color foregroundColor;
    BorderSide borderSide;
    
    switch (variant) {
      case ButtonVariant.primary:
        backgroundColor = theme.primaryColor;
        foregroundColor = theme.colorScheme.onPrimary;
        borderSide = BorderSide.none;
        break;
      case ButtonVariant.secondary:
        backgroundColor = theme.colorScheme.secondary;
        foregroundColor = theme.colorScheme.onSecondary;
        borderSide = BorderSide.none;
        break;
      case ButtonVariant.outlined:
        backgroundColor = Colors.transparent;
        foregroundColor = theme.primaryColor;
        borderSide = BorderSide(color: theme.primaryColor, width: 1);
        break;
      case ButtonVariant.text:
        backgroundColor = Colors.transparent;
        foregroundColor = theme.primaryColor;
        borderSide = BorderSide.none;
        break;
    }
    
    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: borderSide,
      ),
      elevation: variant == ButtonVariant.primary ? 2 : 0,
    );
    
    Widget child = isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: foregroundColor,
              strokeWidth: 2,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
    
    final button = ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: buttonStyle,
      child: child,
    );
    
    if (fullWidth) {
      return SizedBox(
        width: double.infinity,
        child: button,
      );
    }
    
    return button;
  }
}