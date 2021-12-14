import 'package:flow_graph/src/graph_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'graph.dart';
import 'render/preview_connect_render.dart';

class DraggableFlowGraphView<T> extends StatefulWidget {
  const DraggableFlowGraphView({
    Key? key,
    required this.root,
    this.enableDelete = true,
    this.direction = Axis.horizontal,
    this.centerLayout = false,
    required this.builder,
    this.willConnect,
    this.willAccept,
  }) : super(key: key);

  final GraphNode<T> root;
  final Axis direction;
  final bool enableDelete;
  final bool centerLayout;
  final NodeWidgetBuilder<T> builder;
  final WillConnect<T>? willConnect;
  final WillAccept<T>? willAccept;

  @override
  _DraggableFlowGraphViewState<T> createState() =>
      _DraggableFlowGraphViewState<T>();
}

class _DraggableFlowGraphViewState<T> extends State<DraggableFlowGraphView<T>> {
  late Graph _graph;
  final GlobalKey _graphViewKey = GlobalKey();
  RenderBox? _targetRender;

  RelativeRect? _currentPreviewNodePosition;
  GraphNode<T>? _currentPreviewEdgeNode;
  Offset _previewConnectStart = Offset.zero;
  Offset _previewConnectEnd = Offset.zero;

  final _previewConnectRender = PreviewConnectRender();
  final _controller = GraphViewController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: RawKeyboardListener(
        focusNode: FocusNode(),
        onKey: (keyEvent) {
          if (keyEvent is RawKeyDownEvent) {
            if (widget.enableDelete &&
                    keyEvent.logicalKey == LogicalKeyboardKey.backspace ||
                keyEvent.logicalKey == LogicalKeyboardKey.delete) {
              for (var n in _graph.nodes) {
                if (n.focusNode.hasFocus && !n.isRoot) {
                  setState(() {
                    n.deleteSelf();
                  });
                  break;
                }
              }
            }
          }
        },
        child: Focus(
          child: Builder(
            builder: (context) {
              _graph = Graph(
                  nodes: _linearNodes(context, widget.root),
                  direction: widget.direction,
                  centerLayout: widget.centerLayout);
              return DragTarget<GraphNodeFactory<T>>(
                builder: (context, candidate, reject) {
                  return GraphView(
                    key: _graphViewKey,
                    controller: _controller,
                    graph: _graph,
                    onPaint: (canvas) {
                      if (_previewConnectStart.distance > 0 &&
                          _previewConnectEnd.distance > 0) {
                        _previewConnectRender.render(
                            context: context,
                            canvas: canvas,
                            start: Offset(_previewConnectStart.dx,
                                _previewConnectStart.dy),
                            end: Offset(
                                _previewConnectEnd.dx, _previewConnectEnd.dy),
                            direction: _graph.direction);
                      }
                    },
                  );
                  // return GestureDetector(
                  //   onTap: () {
                  //     Focus.of(context).requestFocus(FocusNode());
                  //   },
                  //   onPanUpdate: (details) {
                  //     //limit pan position
                  //     var graphSize = _graph.computeSize();
                  //     var boardSize = (_boardKey.currentContext
                  //                 ?.findRenderObject() as RenderBox?)
                  //             ?.size ??
                  //         Size.zero;
                  //     double dx = 0, dy = 0;
                  //     if (graphSize.width > boardSize.width) {
                  //       dx = _boardPosition.dx + details.delta.dx;
                  //       if (dx > 0) {
                  //         dx = 0;
                  //       } else if (dx <
                  //           boardSize.width -
                  //               graphSize.width -
                  //               kMainAxisSpace) {
                  //         // dx < -(graphSize.width - boardSize.width + kMainAxisSpace)
                  //         dx = boardSize.width -
                  //             graphSize.width -
                  //             kMainAxisSpace;
                  //       }
                  //     }
                  //     if (graphSize.height > boardSize.height) {
                  //       dy = _boardPosition.dy + details.delta.dy;
                  //       if (dy > 0) {
                  //         dy = 0;
                  //       } else if (dy <
                  //           boardSize.height -
                  //               graphSize.height -
                  //               kMainAxisSpace) {
                  //         //dy < -(graphSize.height - boardSize.height + kMainAxisSpace)
                  //         dy = boardSize.height -
                  //             graphSize.height -
                  //             kMainAxisSpace;
                  //       }
                  //     }
                  //
                  //     setState(() {
                  //       _boardPosition = Offset(dx, dy);
                  //     });
                  //   },
                  //   child: ClipRect(
                  //     child: GraphBoard(
                  //       key: _boardKey,
                  //       graph: _graph,
                  //       previewConnectStart: _previewConnectStart,
                  //       previewConnectEnd: _previewConnectEnd,
                  //       position: _boardPosition,
                  //     ),
                  //   ),
                  // );
                },
                onWillAccept: (factory) => factory != null,
                onAccept: (factory) {
                  _acceptNode(context, factory.createNode());
                },
                onLeave: (factory) {
                  _removePreviewEdge();
                },
                onMove: (details) {
                  var target = _graphViewKey.currentContext!.findRenderObject()
                      as RenderBox;
                  var localOffset = target.globalToLocal(details.offset);
                  _previewConnectEdge(context, localOffset);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _acceptNode(BuildContext context, GraphNode<T> node) {
    if (_currentPreviewEdgeNode != null) {
      _currentPreviewEdgeNode!.addNext(node);
      _removePreviewEdge();
    }
  }

  void _addPreviewEdge(BuildContext context, GraphNode<T> node) {
    node.addNext(
        PreviewGraphNode(color: Theme.of(context).colorScheme.secondary));
    setState(() {
      _currentPreviewNodePosition = node.element.position;
      _currentPreviewEdgeNode = node;
    });
  }

  void _removePreviewEdge() {
    if (_currentPreviewEdgeNode == null) {
      return;
    }
    for (var n in _currentPreviewEdgeNode!.nextList) {
      if (n is PreviewGraphNode) {
        _currentPreviewEdgeNode!.nextList.remove(n);

        break;
      }
    }
    setState(() {
      _currentPreviewEdgeNode = null;
      _currentPreviewNodePosition = null;
    });
  }

  void _previewConnectEdge(BuildContext context, Offset offset) {
    if (_currentPreviewNodePosition == null ||
        !_canConnectToPosition(_currentPreviewNodePosition!, offset)) {
      if (_currentPreviewEdgeNode != null) {
        _removePreviewEdge();
      }
      for (var n in _graph.nodes) {
        if (n is! PreviewGraphNode &&
            _canConnectToPosition(n.element.position, offset) &&
            (widget.willConnect == null ||
                widget.willConnect!(n as GraphNode<T>))) {
          _addPreviewEdge(context, n as GraphNode<T>);
          break;
        }
      }
    }
  }

  bool _canConnectToPosition(RelativeRect nodePosition, Offset point) {
    if (_graph.direction == Axis.horizontal) {
      return nodePosition
          .offset(_controller.position)
          .spreadSize(Size(kMainAxisSpace, kCrossAxisSpace))
          .contains(point);
    } else if (_graph.direction == Axis.vertical) {
      return nodePosition
          .offset(_controller.position)
          .spreadSize(Size(kCrossAxisSpace, kMainAxisSpace))
          .contains(point);
    }
    return false;
  }

  //bfs
  List<GraphNode> _linearNodes(BuildContext context, GraphNode<T> root) {
    _initialNodeElement(context, root);
    var walked = <GraphNode>[root];
    var visited = <GraphNode>[root];

    while (walked.isNotEmpty) {
      var currentNode = walked.removeAt(0);
      if (currentNode.nextList.isNotEmpty) {
        for (var i = 0; i < currentNode.nextList.length; i++) {
          var node = currentNode.nextList[i];
          if (!visited.contains(node)) {
            if (node is! PreviewGraphNode) {
              _initialNodeElement(context, node as GraphNode<T>);
            }
            walked.add(node);
            visited.add(node);
          }
        }
      }
    }
    return visited;
  }

  void _initialNodeElement(BuildContext context, GraphNode<T> node) {
    node.initialElement(
      overflowPadding: const EdgeInsets.all(14),
      child: _NodeWidget(
        node: node,
        graphDirection: widget.direction,
        enableDelete: widget.enableDelete,
        child: widget.builder(context, node),
        onDelete: () {
          setState(() {
            node.deleteSelf();
          });
        },
        onPreviewConnectStart: (position) {
          _targetRender ??=
              _graphViewKey.currentContext!.findRenderObject() as RenderBox;
          _previewConnectStart = _targetRender!.globalToLocal(position);
        },
        onPreviewConnectMove: (position) {
          _targetRender ??=
              _graphViewKey.currentContext!.findRenderObject() as RenderBox;
          setState(() {
            _previewConnectEnd = _targetRender!.globalToLocal(position);
          });
        },
        onPreviewConnectStop: (position) {
          _targetRender ??=
              _graphViewKey.currentContext!.findRenderObject() as RenderBox;
          var localPosition = _targetRender!.globalToLocal(position);
          //concern board offset
          var targetNode =
              _graph.nodeOf<T>(localPosition - _controller.position);
          if (targetNode != null &&
              widget.willAccept?.call(targetNode) == true) {
            //connect to node
            node.addNext(targetNode);
          }
          setState(() {
            _previewConnectStart = Offset.zero;
            _previewConnectEnd = Offset.zero;
          });
        },
      ),
    );
  }
}

class _NodeWidget extends StatefulWidget {
  const _NodeWidget(
      {Key? key,
      required this.child,
      this.enableDelete = true,
      required this.node,
      required this.graphDirection,
      this.onDelete,
      this.onPreviewConnectStart,
      this.onPreviewConnectMove,
      this.onPreviewConnectStop})
      : super(key: key);

  final Widget child;
  final bool enableDelete;
  final GraphNode node;
  final Axis graphDirection;
  final VoidCallback? onDelete;
  final void Function(Offset)? onPreviewConnectStart;
  final void Function(Offset)? onPreviewConnectMove;
  final void Function(Offset)? onPreviewConnectStop;

  @override
  _NodeWidgetState createState() => _NodeWidgetState();
}

class _NodeWidgetState extends State<_NodeWidget> {
  bool _hovered = false;
  bool _currentFocus = false;
  bool _previewConnecting = false;

  @override
  void initState() {
    _currentFocus = widget.node.focusNode.hasFocus;
    widget.node.focusNode.addListener(() {
      if (_currentFocus != widget.node.focusNode.hasFocus) {
        setState(() {
          _currentFocus = widget.node.focusNode.hasFocus;
        });
      }
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var focusColor = Theme.of(context).colorScheme.secondaryVariant;
    var renderBox = context.findRenderObject() as RenderBox?;
    var boxSize = Size.zero;
    if (renderBox != null) {
      boxSize = renderBox.size;
    }
    return GestureDetector(
      onTap: () {
        Focus.of(context).requestFocus(widget.node.focusNode);
      },
      onPanUpdate: (details) {},
      onSecondaryTapUp: (details) {
        if (widget.enableDelete && !widget.node.isRoot) {
          showMenu(
              context: context,
              elevation: 6,
              position: RelativeRect.fromLTRB(
                details.globalPosition.dx,
                details.globalPosition.dy,
                details.globalPosition.dx,
                details.globalPosition.dy,
              ),
              items: [
                PopupMenuItem(
                  child: const Text('删除'),
                  value: 'delete',
                  onTap: () {
                    setState(() {
                      widget.onDelete?.call();
                    });
                  },
                )
              ]);
        }
      },
      child: MouseRegion(
        onEnter: (event) {
          setState(() {
            _hovered = true;
          });
        },
        onExit: (event) {
          setState(() {
            _hovered = false;
          });
        },
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(
                    color: (_currentFocus || _previewConnecting)
                        ? focusColor
                        : _hovered
                            ? focusColor.withAlpha(180)
                            : Colors.transparent,
                    width: 2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: widget.child,
            ),
            if (_hovered || _currentFocus || _previewConnecting)
              widget.graphDirection == Axis.horizontal
                  ? Positioned(
                      top: (boxSize.height - 20) / 2,
                      right: 0,
                      child: Listener(
                        onPointerDown: (event) {
                          var center = Offset(
                              event.position.dx - event.localPosition.dx + 10,
                              event.position.dy - event.localPosition.dy + 10);
                          widget.onPreviewConnectStart?.call(center);
                          _previewConnecting = true;
                        },
                        onPointerMove: (event) {
                          widget.onPreviewConnectMove?.call(event.position);
                        },
                        onPointerUp: (event) {
                          widget.onPreviewConnectStop?.call(event.position);
                          _previewConnecting = false;
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.secondaryVariant,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 12,
                          ),
                        ),
                      ),
                    )
                  : Positioned(
                      left: (boxSize.width - 20) / 2,
                      bottom: 0,
                      child: Listener(
                        onPointerDown: (event) {
                          var center = Offset(
                              event.position.dx - event.localPosition.dx + 10,
                              event.position.dy - event.localPosition.dy + 10);
                          widget.onPreviewConnectStart?.call(center);
                          _previewConnecting = true;
                        },
                        onPointerMove: (event) {
                          widget.onPreviewConnectMove?.call(event.position);
                        },
                        onPointerUp: (event) {
                          widget.onPreviewConnectStop?.call(event.position);
                          _previewConnecting = false;
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.secondaryVariant,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_downward_rounded,
                            size: 12,
                          ),
                        ),
                      ),
                    )
          ],
        ),
      ),
    );
  }
}