"""Classify a manually aligned 2:1 face crop, not a whole camera scene."""
from pathlib import Path
import argparse,json
import numpy as np
from PIL import Image,ImageOps
import torch
from train import Model,norm

ap=argparse.ArgumentParser();ap.add_argument('image',type=Path);ap.add_argument('--box',type=int,nargs=4,metavar=('LEFT','TOP','RIGHT','BOTTOM'));args=ap.parse_args()
root=Path(__file__).resolve().parent
im=ImageOps.exif_transpose(Image.open(args.image)).convert('L')
if args.box:im=im.crop(args.box)
arr=norm(np.array(im));net=Model();ck=torch.load(root/'model_float.pt',map_location='cpu',weights_only=True);net.load_state_dict(ck['state_dict']);net.eval()
r=json.loads((root/'training_report.json').read_text(encoding='utf-8'))
with torch.no_grad():prob=net(torch.tensor(arr.copy()).float()[None,None]/255).softmax(1)[0];v,ix=prob.topk(2)
cls=int(ix[0]);rejected=float(v[0])<r['reject_probability'] or float(v[0]-v[1])<r['reject_margin']
if rejected:cls=0
print(json.dumps(dict(class_id=cls,name_zh=ck['labels_zh'][cls],rejected_by_threshold=rejected,softmax_scores={n:float(p) for n,p in zip(ck['labels_zh'],prob)},scope='Manual face crop only; softmax values are not calibrated probabilities.'),ensure_ascii=False,indent=2))
