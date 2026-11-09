"""Shared ML input preprocessing, also used by the photo diagnostic pipeline."""
import numpy as np
from PIL import Image, ImageOps

def input_array(image):
    # One resampling operation; no artificial blur, JPEG degradation or sharpening.
    arr=np.array(ImageOps.exif_transpose(image).convert('L').resize((32,32), Image.Resampling.BOX), copy=True)
    # Integer per-ROI contrast normalization. Needs the same stage in future FPGA RTL.
    lo=int(arr.min());span=int(arr.max())-lo
    if span<16:return np.zeros_like(arr)
    return (((arr.astype(np.int32)-lo)*255+span//2)//span).astype(np.uint8)

def rectify(image, quad, size):
    """Manually annotated TL,TR,BR,BL -> rectangular input; not automatic detection."""
    w,h=size; dst=[(0,0),(w-1,0),(w-1,h-1),(0,h-1)]
    a=[];b=[]
    for (x,y),(u,v) in zip(dst,quad):
        a.extend([[x,y,1,0,0,0,-u*x,-u*y],[0,0,0,x,y,1,-v*x,-v*y]])
        b.extend([u,v])
    coeff=np.linalg.solve(np.array(a,dtype=float),np.array(b,dtype=float))
    return image.transform(size, Image.Transform.PERSPECTIVE, coeff, Image.Resampling.BICUBIC)

def fractional_crop(image, box):
    return image.crop(tuple(round(v*(image.width if i%2==0 else image.height)) for i,v in enumerate(box)))
