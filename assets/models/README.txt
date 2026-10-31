Required TensorFlow Lite models:

- yolov8n.tflite: detector input [1,3,640,640] float32 RGB in [0,1];
  output [1,8,8400] float32.
- mobilenetv3.tflite: classifier input [1,224,224,3] float32 RGB in [0,255];
  output [1,4] float32 softmax probabilities in AB, AG, AN, CQ order.
