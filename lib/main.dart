import 'package:flutter/material.dart';
import "node.dart";
import "line.dart";

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MovableNodeScreen(),
    );
  }
}

class MovableNodeScreen extends StatefulWidget {
  const MovableNodeScreen({super.key});

  @override
  State<MovableNodeScreen> createState() => _MovableNodeScreenState();
}

class _MovableNodeScreenState extends State<MovableNodeScreen> {

  //Resets the screen to blank
  void _reset() {
    setState(() {
      positions = [];
      lineIndices = [];
    });
  }

  List<Node> nodes = [];
  List<List<double>> positions = [];

  List<CustomPaint> lines = [];
  List<List<int>> lineIndices = [];

  //Creates lists to display nodes and lines as children in stack
  void _buildScreen() {
    nodes = [];
    lines = [];
    for (int i = 0; i < positions.length; i++) {
      nodes.add(Node(position: Offset(positions[i][0], positions[i][1])));
    }

    for (int i = 0; i < lineIndices.length; i++) {
      lines.add(
        CustomPaint(

          painter: Line(
            nodeA: Offset(
              positions[lineIndices[i][0]][0] + 50,
              positions[lineIndices[i][0]][1] + 50,
            ),
            nodeB: Offset(
              positions[lineIndices[i][1]][0] + 50,
              positions[lineIndices[i][1]][1] + 50,
            ),
          ),
        ),
      );
    }
  }

  int selectedIndex = -1;
  int selectedIndex2 = -1;

  void resetSelected() {
    selectedIndex = -1;
    selectedIndex2 = -1;
  }

  bool lineMode = false;

  void toggleLineMode() {
    lineMode = !lineMode;
    setState(() {});
  }

  //Returns the index of a given node
  int _selectIndex(Offset position) {
    double y = position.dy - 50;
    double x = position.dx - 50;
    for (int i = 0; i < positions.length; i++) {
      if (nodes[i].containsPoint(x, y)) {
        return i;
      }
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    _buildScreen();
    //Might be needed for screen size
    //double screen_width = MediaQuery.of(context).size.width;    // Screen width
    //double screen_height = MediaQuery.of(context).size.height;  // Screen height
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: () {
        toggleLineMode();
      }),
      appBar: AppBar(
        title: const Text("Automata Designer"),
      ),
      body: Stack(
        children: [
          GestureDetector(
            //Add node on double tap
            onDoubleTapDown: (details) {
              setState(() {
                Offset position = details.localPosition;
                positions.add([position.dx-50, position.dy-50]);
              });
              debugPrint("Positions: $positions");
            },
            onLongPress: () => _reset(),
          ),

          Stack(
            children: lines,
          ),
          Stack(
            children: nodes,
          ),
          /*
          TODO:
          Rework this to be toggles on
          by a floating point button.
          Useless as of current
           */
          IgnorePointer(
            ignoring: false,
            child: GestureDetector(
              //TODO: Implement Line Drawing
              //Select which nodes is dragged
              onPanStart: (details) {
                resetSelected();
                Offset position = details.localPosition;
                selectedIndex = _selectIndex(position);
              },
              //Deselect when stopped dragging
              onPanEnd: (details) {
                if (lineMode) {
                  Offset position = details.localPosition;
                  selectedIndex2 = _selectIndex(position);
                  }
                  if (selectedIndex != -1 && selectedIndex2 != -1) {
                    lineIndices.add([selectedIndex, selectedIndex2]);
                    setState(() {});
                  }
                },
              //Drag node
              onPanUpdate: (details) {
                if (selectedIndex != -1 && !lineMode) {
                  positions[selectedIndex][0] += details.delta.dx;
                  positions[selectedIndex][1] += details.delta.dy;
                  setState(() {});
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}