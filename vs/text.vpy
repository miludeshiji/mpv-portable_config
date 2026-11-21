### Real-ESRGAN 放大后通过RIFE (v4+) 补帧，性能要求极高，N卡专用

import vapoursynth as vs
from vapoursynth import core
import k7sfunc as k7f

clip = video_in

############
# 用户选项 #
############

H_Pre = 720
Lt_Hd = True
Lt_D2k = False
Model_e = 5009
Model_r = 46
Ext_Proc = False
T_Tta = False
Fps_Num = 2
Fps_Den = 1
Sc_Mode = 0
Gpu = 0
Gpu_T = 2
St_Eng = False
Ws_Size = 0
H_Max = 1440
Lk_Fmt = False

## H_Pre 	整数，预降低处理源高度
## Lt_Hd 	<True|False> 是否对超过HD分辨率（720P）的源进行处理
## Lt_D2k 	<True|False> 是否对超过DCI2K分辨率的源进行补帧
## Model1 	<0|2|5005|5006|5007|5008|5009|5010> ESRGAN_NV使用的模型
## Model2 	<46|422|4221> RIFE_NV使用的模型，分别对应 4.6 4.22 4.22lite
## Ext_Proc	<True|False> 是否使用外部的填充裁切处理
## T_Tta 	<True|False> 是否使用ensemble版模型
## Fps_Num 	整数，Fps_Num/Fps_Den 的值即帧率倍数
## Fps_Den 	整数
## Sc_Mode 	<0|1|2> 场景切换检测的模式，0为禁用
## Gpu 		使用的显卡序号，0为排序一号
## Gpu_T 	<1|2|3> 使用的显卡线程数
## St_Eng 	<True|False> 是否使用静态引擎（需要对不同分辨率的源各进行预处理）；动态引擎自适应不同分辨率（64²→DCI2K）
## Ws_Size 	<0~1024> 约束显存（MiB），静态引擎的最小值为128（动态引擎自动双倍），设为低于此数的值即为不限制
## H_Max 	整数，输出高度限制（填你的显示器高度）
## Lk_Fmt 	<True|False> 是否锁定像素格式为yuv420p8

ret = k7f.FMT_CTRL(clip, h_max=container_fps, h_ret=True)

clip = k7f.FMT_CTRL(clip, h_max=H_Pre, fmt_pix=1 if Lk_Fmt else 0) ## 第一次
clip = k7f.ESRGAN_NV(clip, lt_hd=Lt_Hd, model=Model_e, gpu=Gpu, gpu_t=Gpu_T, st_eng=St_Eng, ws_size=Ws_Size)
clip = k7f.FMT_CTRL(clip, h_max=H_Max, fmt_pix=1 if Lk_Fmt else 0) ## 第二次
clip = k7f.RIFE_NV(clip, lt_d2k=Lt_D2k, model=Model_r, ext_proc=Ext_Proc, t_tta=T_Tta, fps_in=container_fps, fps_num=Fps_Num, fps_den=Fps_Den, sc_mode=Sc_Mode, gpu=Gpu, gpu_t=Gpu_T, st_eng=St_Eng, ws_size=Ws_Size)

clip.set_output()