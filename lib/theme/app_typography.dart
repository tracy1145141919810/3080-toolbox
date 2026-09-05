import 'package:flutter/material.dart';

/// Explicit control typography: icon and plain buttons must resolve the same
/// font face and metrics, independently of their surrounding text widgets.
const toolboxControlTextStyle = TextStyle(
  fontFamily: 'ToolboxCJK',
  fontSize: 14,
  fontWeight: FontWeight.w500,
  fontStyle: FontStyle.normal,
  letterSpacing: 0,
  wordSpacing: 0,
  height: 1.5,
  textBaseline: TextBaseline.alphabetic,
);
