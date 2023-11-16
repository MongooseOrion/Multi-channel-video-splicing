import serial
import time

def send_data(serial_port, data):
    try:
        # 打开串口
        ser = serial.Serial(serial_port, baudrate=9600, timeout=1)

        # 将数据转换为十六进制格式
        hex_data = format(data, '02x')

        # 发送数据
        ser.write(bytearray.fromhex(hex_data))

        # 关闭串口
        ser.close()

        print(f"成功发送数据: {hex_data}")
    except Exception as e:
        print(f"发送数据时出错: {str(e)}")

# 设置串口号
serial_port = 'COM1'  

# 设置要发送的8位数据
data_to_send = 0xAB

# 发送数据
send_data(serial_port, data_to_send)
