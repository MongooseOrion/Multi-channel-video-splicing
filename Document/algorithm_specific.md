<!-- =====================================================================
* Copyright (c) 2023, MongooseOrion.
* All rights reserved.
*
* The following code snippet may contain portions that are derived from
* OPEN-SOURCE communities, and these portions will be licensed with: 
*
* <NULL>
*
* If there is no OPEN-SOURCE licenses are listed, it indicates none of
* content in this Code document is sourced from OPEN-SOURCE communities. 
*
* In this case, the document is protected by copyright, and any use of
* all or part of its content by individuals, organizations, or companies
* without authorization is prohibited, unless the project repository
* associated with this document has added relevant OPEN-SOURCE licenses
* by github.com/MongooseOrion. 
*
* Please make sure using the content of this document in accordance with 
* the respective OPEN-SOURCE licenses. 
* 
* THIS CODE IS PROVIDED BY https://github.com/MongooseOrion. 
* FILE ENCODER TYPE: UTF-8
* ========================================================================
-->
# 算法细节

## 任意角度旋转

旋转后的坐标通常不是按照显示顺序排列的，而 HDMI 输出需要按照 VESA 时序要求将图像数据按行列顺序进行输出。因此，我们需要解决如何将旋转后的图像数据重新排序以满足 HDMI 输出的顺序要求。

要实现这一点，可以考虑使用反向映射（Backward Mapping）和帧缓存的方法。我们从输出图像的每个像素点反向计算出对应的原始图像中的坐标，从而直接生成按顺序排列的图像数据。

为了避免使用浮点运算，可以将三角函数的值预先计算并放大一定倍数（比如 256 倍），然后存储在 ROM 中。每当需要进行坐标变换时，可以直接使用这些放大的系数进行乘法运算，并在计算结束后通过移位操作将结果还原到原始坐标系统。

在每一个像素 `(x', y')`的位置，需要计算其对应的原始图像中的坐标 `(x, y)`。公式如下：

$$\begin{bmatrix}
x \\
y
\end{bmatrix} = 
\frac{1}{256}
\begin{bmatrix}
\cos(\theta) \times 256 & \sin(\theta) \times 256 \\
-\sin(\theta) \times 256 & \cos(\theta) \times 256
\end{bmatrix} 
\begin{bmatrix}
x' \\
y'
\end{bmatrix}$$

由于 $\cos(θ) \times 256$ 和 $\sin(θ) \times 256$ 都是整数，我们可以直接进行乘法运算，并在结果得到后右移 8 位来实现除以 256 的操作。

## FPGA 固定角度旋转实现

  1. AXI 突发读取操作

      每一行有 960 个像素，按照代码设定，`burst_len=10`。每次 AXI 读事务读取 160 个像素（256 位数据对应 16 个像素，`burst_len=10` 则读取 160 个像素）。

      因此，读取完整一行 960 个像素需要 6 次 AXI 突发读取操作。

  2. `addr_cnt` 的作用
      `addr_cnt` 用来计数每行的读事务数。当 `addr_cnt` 达到 6 时（即读完 960 个像素），`addr_cnt` 复位为 0，开始下一行的读取。

       每次 `addr_cnt` 增加时，`reg_axi_araddr` 用于更新 AXI 读地址。尽管 `rotate_mode=1` 时 `reg_axi_araddr_5` 是倒序更新的，但由于一次突发读取会返回多个顺序排列的像素，这些像素还是按顺序排列的。

  3. RAM 写入操作

       AXI 从 DDR 中顺序读取出一行的 160 个像素，按正序写入 RAM。这个过程是连续进行的，直到完成一整行（960 个像素）的读取。
       
       写入 RAM 的地址 `wr_addr` 逐次增加，因此一行数据在 RAM 中是顺序存储的。

  4. RAM 读取操作

       在 `rotate_mode=1` 的情况下，读取操作是按行完全逆序进行的。也就是说，`rd_addr` 从高地址开始（例如 959），逐渐减少直到 0。

       这样，通过逆序读取，输出的数据是按原行像素的倒序排列，达到了 180 度旋转的效果。