# 基于 FPGA 的多路视频拼接系统

此项目用于将多路视频源拼合输出为一路视频源，其中 3 路为照相机源，1 路为 HDMI 源。同时还具备图像旋转和缩放功能，以下是关键功能参数表：

| 受支持的类别 | 值 |
| :--- | :--- |
|照相机输入分辨率 | $1280\times 720$ |
|HDMI输入分辨率 | $1280\times 720$ |
| 照相机输入帧率 | 30 |
| HDMI输入帧率 | 60 |
| 输入通道数 | 4 |
| 显示通道数 | 5 |
| 支持的缩放倍率 | 0.25，0.5~0.75 步长为 0.015（对于输入分辨率而言） |
| 支持的旋转角度 | $0^\circ$, ${180}^\circ$ |
| 支持的翻转模式 | 水平、垂直 |
| 支持的图像处理操作 | 亮度调整、色相调整、灰阶显示 |
| HDMI输出分辨率 | $1280\times 720$ |
| 支持的HDMI输出帧率 | 30, 60 |
| 串口控制 | 8位 |
| 字符显示 | 固化字符/网络传输 |


开发平台：
  * 紫光同创 PGL50H-6FBG484，拥有 32bit 输入位宽，通过一组 AXI 接口输入；

## 仓库目录

```
  |-- Document                  // 存放项目文档
  |-- FPGA                      // 存放工程文件，例如比特流文件和 ROM 数据
    |-- bitstream_backup
  |-- RTL                       // Verilog 代码
  |-- Software                  // Python 代码
```

## 硬件设计

### 系统总体结构

下图显示了该系统的结构拓扑图：

<div align = 'center'><img src = './Document\pic\屏幕截图 2023-11-13 143918.png' width = '500' title = '系统拓扑图'></div>

该系统可输入 3 路摄像头信号，1 路 HDMI 信号，通过分别缩放为输出视频画面的 $\frac{1}{16}$ 大小，排布在画面的上部。另外，在下部由电脑传入串口数据来控制显示的视频通道，此内容会被缩放为输出视频画面的 $\frac{9}{16}$ 。而输出视频画面剩余的 $\frac{6}{16}$ 画面空间，将会显示预设字符串。如果你对 AXI 总线比较了解，也可以尝试增加更多的输入源，由于在设计时已经将关键图像参数全部参数化，使得接入更多图像源成为可能。

详细的输出视频画面分布可见下图：
<div align = 'center'><img src ='./Document\pic\屏幕截图 2023-11-13 150736.png' width = '500' title = '输出视频画面分布图'></div>

### 图像数据写入 DDR 逻辑

由于该芯片只提供 1 个 DDR AXI 接口，因此所有读写操作必须经过仲裁，保证在同一时间只有一路信号占用 AXI 总线通道。

对于写缓冲器的设计，采用的是 BRAM FIFO，当存入的数据量满足一次突发写所需的数据量时，拉高数据准备好信号。以下是伪代码逻辑：

```verilog
`define INPUT CMOS_1

fifo_wr u_fifo_wr(
    .wr_en          (wr_en      ),
    .wr_data        (wr_data    ),  // [15:0]
    .almost_full    (data_ready ),
    .rd_en          (rd_valid   ),
    .rd_data        (axi_wdata  )   // [255:0]
);

assign wr_en = frame_href;
assign wr_data = rgb565;    // [15:0]

parameter almost_full_number = 255 * axi_awlen;
```

AXI 时分复用利用状态机实现，当任一缓冲存储模块的 `data_ready` 信号为高，则开始占用 AXI 总线突发传输一次，然后跳转到下一路视频传输。

关于地址，已为每路视频开辟 2 帧的存储空间，以便于进行图像处理。在每路视频传输时，地址会赋值基地址初值，当一帧存满时，同样赋值另一个基地址值。基地址设置可见下述伪代码：
```verilog
// 地址偏移量
parameter FRAME_ADDR_OFFSET_1 = 'd30_000;
parameter FRAME_ADDR_OFFSET_2 = 'd260_000;
parameter   ADDR_OFFSET_1 = 'd0,                    
            ADDR_OFFSET_2 = FRAME_ADDR_OFFSET_1 * 2,  
            ADDR_OFFSET_3 = ADDR_OFFSET_2 + 2 * (FRAME_ADDR_OFFSET_1),
            ADDR_OFFSET_4 = ADDR_OFFSET_3 + 2 * (FRAME_ADDR_OFFSET_1),
            ADDR_OFFSET_5 = ADDR_OFFSET_4 + 2 * (FRAME_ADDR_OFFSET_1);
parameter ADDR_STEP = BURST_LEN * 8;       // 首地址自增步长，1 个地址 32 位数据，这与芯片的 DQ 宽度有关
```

### 图像数据从 DDR 读取逻辑

对于写入 DDR 的逻辑，必须采用 “传输一次则握手 `awvalid && arready` 一次” 的机制，这是因为每次只对一路视频传输一个突发长度的数据，因此必须依赖握手机制和 `wlast` 信号对数据的 “钳制” 作用。

然而对于读取来说，对一路视频地址空间的读取可以不局限在一个突发长度的数据传输中，而可以多读取几个突发长度，因此可以一直拉高 `arvalid` 信号，等待某一通道完成传输后再拉低，也即采用 AXI outstanding 机制。

不同于写入的逻辑，读取的逻辑必须是按照实际输出画面的先后通道，动态地调整所需要读取的地址空间，只有这样才能保证重新生成的 HDMI 时序所需要使用的像素数据是按照实际的显示顺序排布的。读取逻辑伪代码如下述所示：

```verilog
case(buf_rd_state)
  CH_1: begin
    if(pixel_count == VIDEO_WIDTH / 4)  begin
      buf_rd_state <= CH_2;
    end
    else begin
      buf_rd_state <= buf_rd_state;
    end
  end
  CH_2: begin
    if(pixel_count == VIDEO_WIDTH / 4)  begin
      buf_rd_state <= CH_3;
    end
    else begin
      buf_rd_state <= buf_rd_state;
    end
  end
  CH_3: begin
    if(pixel_count == VIDEO_WIDTH / 4)  begin
      buf_rd_state <= CH_4;
    end
    else begin
      buf_rd_state <= buf_rd_state;
    end
  end
  CH_4: begin
    if((pixel_count == VIDEO_WIDTH / 4)
        && (row_count == VIDEO_HEIGHT / 4))  begin
      buf_rd_state <= CH_5;
    end
    else if((pixel_count == VIDEO_WIDTH / 4)
            && (row_count < VIDEO_HEIGHT / 4)) begin
      buf_rd_state <= CH_1;
    end
    else begin
      buf_rd_state <= buf_rd_state;
    end
  end
  CH_5: begin
    if((pixel_count == VIDEO_WIDTH * (3/4)
        && (row_count == VIDEO_HEIGHT))  begin
      buf_rd_state <= CH_1;
    end
    else begin
      buf_rd_state <= buf_rd_state;
    end
  end
endcase
```

### 图像旋转逻辑

在计算旋转后的坐标后，基于该坐标寻找原图中的数据，如果无法找到对应的数据则不显示，这样可以避免产生空像素的情况。坐标对应关系的计算方法如下述所示：

$$\begin{bmatrix}
  x_0 & y_0 & 1
\end{bmatrix} = 
\begin{bmatrix}
  x_1 & y_1 & 1
\end{bmatrix} = 
\begin{bmatrix}
  \cos(\theta) & -\sin (\theta) & 0 \\
  \sin(\theta) & \cos(\theta) & 0 \\
  0 & 0 & 1
\end{bmatrix}$$

如果想要 RTL 实现三角函数运算是比较困难的，因此可以直接利用查找表来控制运算过程，直接给出每个角度对应三角函数的运算结果。你可以自行查看位于 `RTL` 文件夹中的相关内容。

坐标变换的伪代码如下述所示：
```verilog
assign x_rotate_temp = (x_wire <<< 8) * cos_value - (y_wire <<< 8) * sin_value;	
assign y_rotate_temp = (x_wire <<< 8) * sin_value + (y_wire <<< 8) * cos_value;

assign x_rotate = x_rotate_temp >>> 16;
assign y_rotate = y_rotate_temp >>> 16;
```

### 图像缩放逻辑

通过直接抽取缩放后的坐标对应地址的数据，可实现对图像的缩放，也即对完整的视频抽掉其中的部分像素实现缩放功能，这种方法可以与旋转模块实现无缝集成，降低资源使用率。坐标变换的伪代码如下述所示：

```verilog
assign x_cnt = write_read_len[9:0];
assign y_cnt = write_read_len[31:10];

rd_addr <= scale_value*x_cnt + scale_value*VIDEO_WIDTH*y_cnt;
```

### 其他模块

#### UART 指令控制模块

此模块旨在将电脑传输的串口数据转为控制指令，点击[此处](https://github.com/MongooseOrion/Multi-channel-video-splicing/blob/main/Document/command.md)可查看控制指令对应的功能。

#### 字符显示模块

该模块用于显示字符，包括初始化的固化内容和以太网字符传输模块，固化的 ROM 资源已初始化 16 个字符和所有数字，通过以太网可传输多达 5 个中文字符。

#### 亮度和色相调整模块

该模块用于调整输出图像的亮度和颜色。

## 资源使用量

