import 'package:flutter/material.dart';
import "dart:math";

class Node extends StatefulWidget {
  final Offset position;

  const Node({
    super.key,
    required this.position,
  });

  bool containsPoint(double x, double y) {
    if (pow(x - position.dx, 2) + pow(y - position.dy, 2) < pow(50, 2)) {
      return true;
    } else {
      return false;
    }
  }

  @override
  State<Node> createState() => _NodeState();
}

bool defaultVisibility = false;

class _NodeState extends State<Node> {
  late Color borderColor = Colors.black;
  final FocusNode focusNode = FocusNode();
  late bool internalvisibility = defaultVisibility;

  //Changes the appearance for selected nodes
  void _enabler() {
    setState(() {
      borderColor = Colors.lightBlueAccent;
      focusNode.requestFocus();
    });
  }

  //Disables selected node appearance
  void _disabler() {
    setState(() {
      borderColor = Colors.black;
      focusNode.unfocus();
    });
  }

  @override
  void dispose() {
    super.dispose();
    focusNode.dispose();
  }

  //TODO: Make this useful later
  //List<double> getPosition () {
  //  return [top, left];
  //}

  @override
  void initState() {
    super.initState();
    _enabler();
    focusNode.addListener(_loseFocus);
  }

  void _loseFocus() {
    if (!focusNode.hasFocus) {
      _disabler();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: widget.position.dy,
      left: widget.position.dx,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
          border: Border.all(
            color: borderColor,
            width: 4.0,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: GestureDetector(
                onTap: () {
                    _enabler();
                  },
                onDoubleTap: () {
                  setState(() {
                    internalvisibility = !internalvisibility;
                    _enabler();
                  });
                  //debugPrint("Visibility: $internalvisibility");
                },
                child: TextField(
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontStyle: FontStyle.italic,
                      fontSize: 30,
                      color: borderColor),
                  textAlign: TextAlign.center,
                  focusNode: focusNode, 
                  onEditingComplete: () => _disabler(),
                  onTapOutside: (PointerDownEvent event) => _disabler(),
                  onTap: () => _enabler(), // This is not getting tapped, that needs to be fixed
                  decoration: null, //Removes text-field designs
                ),
            ),
              ),
            //Accept state extra circle
            Center(
                child: IgnorePointer(
                  ignoring: false, //TODO: add accept state toggle
                  child: Visibility(
                    visible: internalvisibility, //TODO: add accept state toggle
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                        onDoubleTap: () {
                          setState(() {
                            internalvisibility = !internalvisibility;
                            _enabler();
                          });
                          //debugPrint("Visibility: $internalvisibility");
                        },
                        onTap: () { 
                          _enabler();
                        },
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: borderColor,
                              width: 4.0,
                            ),
                          ),
                        ),
                    ),
                  ),
                )
            ),
          ],
        ),
      ),
    );
  }
}