import tensorflow as tf
d = tf.lite.Interpreter(model_path='assets/models/yolov8n.tflite')
d.allocate_tensors()
print('D_IN', d.get_input_details()[0]['shape'], d.get_input_details()[0]['dtype'])
print('D_OUT', d.get_output_details()[0]['shape'], d.get_output_details()[0]['dtype'])
c = tf.lite.Interpreter(model_path='assets/models/mobilenetv3.tflite')
c.allocate_tensors()
print('C_IN', c.get_input_details()[0]['shape'], c.get_input_details()[0]['dtype'])
print('C_OUT', c.get_output_details()[0]['shape'], c.get_output_details()[0]['dtype'])
