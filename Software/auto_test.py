import serial
import time
import socket
import codecs
import binascii

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
serial_port = 'COM19' 
udp_host = '192.168.0.2'
udp_port = 8080

input_value = [0xF1,0xF2,0xf3,0xf4,0x2a,0x29,0x28,0x27,0x26,0x24,0x23,0x22,0x21,
               0x20,0x31,0x30,0x41,0x42,0x40,0x61,0x60,0x77,0x77,0x70,
               0x7f,0x7f,0x7f,0x70,0x87,0x87,0x87,0x80]

with open('../FPGA/ethernet_character_1.txt', 'r', encoding = 'UTF-8') as ecfile:
    hex_string = ecfile.read().strip()

 # 创建UDP套接字
udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

#formatted_string = ''.join(['\\x{}'.format(hex_string[i:i+2]) for i in range(0, len(hex_string), 2)])
#byte_data = bytearray.fromhex(''.join(hex_string.split()))

byte_data = bytearray.fromhex(hex_string)
print(' '.join(hex(b) for b in byte_data))

udp_socket.sendto(byte_data, (udp_host, udp_port))
udp_socket.close()
print(f"成功发送UDP数据")


# 设置要发送的8位数据
for i in range(32):
    data_to_send = input_value[i]
    send_data(serial_port, data_to_send)
    time.sleep(3)
