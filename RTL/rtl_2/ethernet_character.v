/* =======================================================================
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
* FILE ENCODER TYPE: GBK
* ========================================================================
*/
// 以太网字符传输和视频叠加

module ethernet_character(
    input                       sys_clk,
    input                        rst_n,
	//hdmi output        
    output                      tmds_clk_p,
    output                      tmds_clk_n,
    output[2:0]                 tmds_data_p,       
    output[2:0]                 tmds_data_n,
	output[3:0]                 rgmii_txd,
	output                      rgmii_txctl,
	output                      rgmii_txc,
	input[3:0]                  rgmii_rxd,
	input                       rgmii_rxctl,
	input                       rgmii_rxc,
    output                      led        
);
wire                            video_clk;
wire                            video_clk5x;

wire[7:0]                       video_r;
wire[7:0]                       video_g;
wire[7:0]                       video_b;
wire                            video_hs;
wire                            video_vs;
wire                            video_de;
wire                            hdmi_hs;
wire                            hdmi_vs;
wire                            hdmi_de;
wire[7:0]                       hdmi_r;
wire[7:0]                       hdmi_g;
wire[7:0]                       hdmi_b;

wire                            osd_hs;
wire                            osd_vs;
wire                            osd_de;
wire[7:0]                       osd_r;
wire[7:0]                       osd_g;
wire[7:0]                       osd_b;

wire [7:0]                      udp_rec_ram_rdata;
wire [10:0]                     udp_rec_ram_read_addr;
wire                            udp_rec_data_valid;

assign hdmi_hs     = osd_hs;
assign hdmi_vs    = osd_vs;
assign hdmi_de     = osd_de;
assign hdmi_r      = osd_r[7:0];
assign hdmi_g      = osd_g[7:0];
assign hdmi_b      = osd_b[7:0];
wire                             sys_clk_g;
wire                             video_clk_w;       
wire                             video_clk5x_w;

GTP_CLKBUFG sys_clkbufg
(
  .CLKOUT                    (sys_clk_g                ),
  .CLKIN                     (sys_clk                  )
);
GTP_CLKBUFG video_clk5xbufg
(
  .CLKOUT                    (video_clk5x               ),
  .CLKIN                     (video_clk5x_w             )
);
GTP_CLKBUFG video_clkbufg
(
  .CLKOUT                    (video_clk                 ),
  .CLKIN                     (video_clk_w               )
);

color_bar color_bar_m0(
	.clk                        (video_clk                ),
	.rst                        (~rst_n                   ),
	.hs                         (video_hs                 ),
	.vs                         (video_vs                 ),
	.de                         (video_de                 ),
	.rgb_r                      (video_r                  ),
	.rgb_g                      (video_g                  ),
	.rgb_b                      (video_b                  )
);


//下面是显示字符的模块,去里面修改字符的显示区域大小和位置
osd_display  osd_display_m0(
	.rst_n                 (rst_n                      ), 
	.pclk                  (video_clk                  ),
	.i_hs                  (video_hs                   ),
	.i_vs                  (video_vs                   ),
	.i_de                  (video_de                   ),
	.i_data                ({video_r,video_g,video_b}  ),
	.o_hs                  (osd_hs                     ),
	.o_vs                  (osd_vs                     ),
	.o_de                  (osd_de                     ),
	.o_data                ({osd_r,osd_g,osd_b}        ),
    .ram_addr              (udp_rec_ram_read_addr      ), //output，输出读取ram的地址
    .q                     (udp_rec_ram_rdata          ),
    .udp_rec_data_valid    (udp_rec_data_valid         )
);

//以太网接收数据的模块
 ethernet_test rec_data(
.sys_clk                   (sys_clk),
.video_clk                 (video_clk), 
.rst_n                     (rst_n),
.rgmii_txd                 (rgmii_txd),
.rgmii_txctl               (rgmii_txctl),
.rgmii_txc                 (rgmii_txc),
.rgmii_rxd                 (rgmii_rxd),
.rgmii_rxctl               (rgmii_rxctl),
.rgmii_rxc                 (rgmii_rxc),
.led                       (led),
.udp_rec_ram_rdata         (udp_rec_ram_rdata) ,//ram读数据
.udp_rec_ram_read_addr     (udp_rec_ram_read_addr), //ram读地址
.udp_rec_data_valid        (udp_rec_data_valid)  
     );
endmodule