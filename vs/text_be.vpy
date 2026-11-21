### 这是优化后的完整vpy脚本内容
import k7sfunc as k7f

clip = video_in
ret = k7f.FMT_CTRL(clip, h_max=1080, h_ret=True)

clip = k7f.FMT_CTRL(clip, h_max=720, fmt_pix=1) ## 第一次
clip = k7f.UAI_NV_TRT(clip, model_pth="Zarxrax_DigitalFlim_SuperUltraCompact_x2_fp16_opset14.onnx", fp16=True, st_eng=True)
clip = k7f.FMT_CTRL(clip, h_max=1440) ## 第二次
clip = k7f.MVT_MQ(clip, fps_in=container_fps)

clip.set_output()