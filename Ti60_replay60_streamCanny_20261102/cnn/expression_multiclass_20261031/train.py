"""Five-class training experiment. Never writes active FPGA weights or RTL."""
from pathlib import Path
import hashlib, json, math, random, shutil, time
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import torch
from torch import nn
from torch.nn import functional as F

ROOT=Path(__file__).resolve().parent
INPUTROOT=ROOT
PROJECT=ROOT.parents[1]
SEED=20261031
LABELS=['other_invalid','teeth_smile','closed_eye_smile','crying','open_eye_open_mouth']
ZH=['其他或无效画面','露齿笑','闭眼微笑','哭泣','睁眼张嘴']
SOURCES=[('微信图片_202610281715_1.jpg',[230,690,1030,1090]),
 ('微信图片_202610281715_2.jpg',[280,630,1040,1010]),
 ('微信图片_202610281715_3.jpg',[280,710,1060,1100]),
 ('微信图片_202610282000_5.jpg',[220,500,900,840])]

class Model(nn.Module):
 def __init__(self):
  super().__init__()
  self.features=nn.Sequential(nn.Conv2d(1,4,3,padding=1),nn.ReLU(),nn.MaxPool2d(2),
   nn.Conv2d(4,8,3,padding=1),nn.ReLU(),nn.MaxPool2d(2),nn.Conv2d(8,8,3,padding=1),nn.ReLU(),nn.AdaptiveAvgPool2d(1))
  self.classifier=nn.Linear(8,5)
 def forward(self,x):return self.classifier(self.features(x).flatten(1))

def norm(a):
 a=cv2.resize(a,(32,32),interpolation=cv2.INTER_AREA)
 lo=int(a.min());span=int(a.max())-lo
 if span<16:return np.zeros((32,32),np.uint8)
 return (((a.astype(np.int32)-lo)*255+span//2)//span).astype(np.uint8)

def augment(a,rng,stress=False):
 # Small geometry/lighting changes; no generative facial edits, no heavy blur.
 a=cv2.resize(a,(128,64),interpolation=cv2.INTER_AREA)
 m=cv2.getRotationMatrix2D((64,32),rng.uniform(-9,9) if stress else rng.uniform(-5,5),rng.uniform(.87,1.13) if stress else rng.uniform(.94,1.06))
 m[0,2]+=rng.uniform(-6,6) if stress else rng.uniform(-3,3)
 m[1,2]+=rng.uniform(-3,3) if stress else rng.uniform(-1.5,1.5)
 a=cv2.warpAffine(a,m,(128,64),flags=cv2.INTER_LINEAR,borderMode=cv2.BORDER_REPLICATE).astype(np.float32)
 a=a*rng.uniform(.7,1.15)+rng.uniform(-20,15)
 a+=np.linspace(-1,1,128)[None,:]*rng.uniform(-16,16)
 a+=rng.normal(0,1 if not stress else 2,a.shape)
 return norm(np.clip(a,0,255).astype(np.uint8))

def build_data():
 (ROOT/'sources').mkdir(exist_ok=True);(ROOT/'previews').mkdir(exist_ok=True)
 faces=[];full=[];metadata=[]
 for cls,(name,box) in enumerate(SOURCES,1):
  p=INPUTROOT/'sources'/name
  if not p.exists():p=PROJECT/'assets/expressions/source'/name
  if p.resolve()!=(ROOT/'sources'/name).resolve():shutil.copy2(p,ROOT/'sources'/name)
  a=np.array(Image.open(p).convert('L'));full.append(a)
  x1,y1,x2,y2=box;faces.append(a[y1:y2,x1:x2])
  metadata.append(dict(class_id=cls,label=LABELS[cls],name_zh=ZH[cls],source='sources/'+name,crop=box,sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
 (ROOT/'labels.json').write_text(json.dumps({'classes':[dict(id=i,label=l,name_zh=ZH[i]) for i,l in enumerate(LABELS)],'mapping':metadata,'excluded':'微信图片_202610281954_4.jpg: red-circle annotation, duplicate of closed-eye smile','semantic_scope':'Four supplied drawing patterns; not general emotion or identity recognition'},ensure_ascii=False,indent=2),encoding='utf-8')
 # Non-face source patches: hair/accessories/clothing; half-face patches deliberately omit one eye or the mouth.
 negatives=[]
 for a,face in zip(full,faces):
  h,w=a.shape
  for box in [(0,0,w//2,h//3),(w//2,0,w,h//3),(0,int(.86*h),w,h), (0,0,w//5,h)]:
   x1,y1,x2,y2=box;negatives.append((a[y1:y2,x1:x2],'hair_accessory_clothing'))
  h,w=face.shape
  for part in [face[:h//2,:],face[h//2:,:],face[:,:w//2],face[:,w//2:]]:negatives.append((part,'partial_face'))
 # Background comes from the top room/window region of the user's photo, never the monitor or tablet.
 photo=Path(r'D:\Wechat\xwechat_files\wxid_oq83a0iyfgkt12_c136\temp\RWTemp\2026-10\75901d85c50c183b8662355800370f11\226774d47257e77aa9c5d69882425b17.jpg')
 backgrounds=sorted((INPUTROOT/'sources').glob('room_background_*.png'))
 if backgrounds:
  for p in backgrounds:
   if p.resolve()!=(ROOT/'sources'/p.name).resolve():shutil.copy2(p,ROOT/'sources'/p.name)
   negatives.append((np.array(Image.open(p).convert('L')),'room_background'))
 elif photo.exists():
  a=np.array(Image.open(photo).convert('L'));h,w=a.shape
  for j,(x1,x2) in enumerate([(0,w//2),(w//2,w)]):
   patch=a[:int(.22*h),x1:x2];Image.fromarray(patch).save(ROOT/'sources'/f'room_background_{j}.png');negatives.append((patch,'room_background'))
 allsets={};seen=set();manifest=[]
 for si,(split,count) in enumerate([('train',128),('synthetic_validation',32),('synthetic_test',32)]):
  rng=np.random.default_rng(SEED+si*1000);xs=[];ys=[]
  for cls in range(5):
   for j in range(count):
    kind='face_drawing'
    while True:
     if cls:a=augment(faces[cls-1],rng,split=='synthetic_test')
     elif j%5 in (0,1,2):
      base,kind=negatives[int(rng.integers(len(negatives)))];a=augment(base,rng,split=='synthetic_test')
     elif j%5==3:
      kind='procedural_lines';base=np.full((64,128),int(rng.integers(100,245)),np.uint8)
      for _ in range(5):cv2.line(base,tuple(rng.integers([0,0],[128,64])),tuple(rng.integers([0,0],[128,64])),int(rng.integers(0,100)),2)
      a=norm(base)
     else:
      kind='blank_or_noise';a=np.zeros((32,32),np.uint8) if j==4 and si==0 else norm(rng.integers(0,256,(64,128),dtype=np.uint8))
     digest=hashlib.sha256(a.tobytes()).hexdigest()
     if digest not in seen:break
    seen.add(digest);xs.append(a);ys.append(cls)
    manifest.append(dict(split=split,index=len(xs)-1,class_id=cls,kind=kind,sha256=digest))
  x=np.stack(xs);y=np.array(ys,np.int64);np.savez_compressed(ROOT/f'{split}.npz',images=x,labels=y);allsets[split]=(x,y)
 # Only a small contact sheet is written, not hundreds of loose generated images.
 font=ImageFont.truetype(r'C:\Windows\Fonts\msyh.ttc',19)
 sheet=Image.new('RGB',(640,5*115),'white');d=ImageDraw.Draw(sheet)
 for cls in range(5):
  d.text((5,cls*115+3),f'{cls} {ZH[cls]}',fill='black',font=font)
  if cls:sheet.paste(Image.fromarray(faces[cls-1]).convert('RGB').resize((200,80)),(0,cls*115+30))
  samples=allsets['train'][0][allsets['train'][1]==cls]
  for k in range(5):sheet.paste(Image.fromarray(samples[k]).convert('RGB').resize((64,64)),(220+80*k,cls*115+35))
 sheet.save(ROOT/'previews/label_and_samples.png')
 (ROOT/'sample_manifest.jsonl').write_text('\n'.join(json.dumps(r) for r in manifest),encoding='utf-8')
 (ROOT/'dataset_report.json').write_text(json.dumps(dict(seed=SEED,counts={k:len(v[1]) for k,v in allsets.items()},independent_originals_per_positive_class=1,source_overlap_between_synthetic_splits=True,exact_normalized_pixel_duplicates_between_splits=0,raw_fpga_camera_frames=0,photo_diagnostics_used_for_training=False,negative_types=sorted(set(r['kind'] for r in manifest if r['class_id']==0))),indent=2),encoding='utf-8')
 return allsets

@torch.no_grad()
def metrics(logits,y,pt=0.,mt=0.):
 probs=logits.softmax(1);v,ix=probs.topk(2,dim=1);pred=ix[:,0].clone();pred[(v[:,0]<pt)|((v[:,0]-v[:,1])<mt)]=0
 cm=torch.zeros((5,5),dtype=torch.int64)
 for a,b in zip(y.tolist(),pred.tolist()):cm[a,b]+=1
 return dict(accuracy=float((pred==y).float().mean()),confusion_matrix=cm.tolist(),per_class_recall=[float(cm[i,i]/max(1,cm[i].sum())) for i in range(5)],predictions=pred.tolist())

def main():
 if (ROOT/'model_float.pt').exists():raise SystemExit('Preserve completed run; output already exists.')
 torch.set_num_threads(4);torch.manual_seed(SEED);random.seed(SEED);np.random.seed(SEED)
 sets=build_data();data={k:(torch.from_numpy(x[:,None].copy()).float()/255,torch.from_numpy(y)) for k,(x,y) in sets.items()}
 net=Model();opt=torch.optim.AdamW(net.parameters(),lr=.006,weight_decay=.0001)
 epochs=160;sched=torch.optim.lr_scheduler.CosineAnnealingLR(opt,epochs,eta_min=.0002)
 best=(float('inf'),0);history=[];start=time.perf_counter()
 x,y=data['train'];vx,vy=data['synthetic_validation']
 for epoch in range(1,epochs+1):
  net.train();loss_sum=0
  for idx in torch.randperm(len(y)).split(64):
   opt.zero_grad();loss=F.cross_entropy(net(x[idx]),y[idx]);loss.backward();opt.step()
   with torch.no_grad():
    for n,p in net.named_parameters():
     if n.endswith('weight'):p.clamp_(-.9921875,.9921875)
   loss_sum+=loss.item()*len(idx)
  sched.step();net.eval()
  with torch.no_grad():vl=net(vx);vloss=float(F.cross_entropy(vl,vy));acc=float((vl.argmax(1)==vy).float().mean())
  history.append(dict(epoch=epoch,train_loss=loss_sum/len(y),val_loss=vloss,val_accuracy=acc))
  if vloss<best[0]:best=(vloss,epoch);torch.save({'state_dict':net.state_dict(),'labels':LABELS,'labels_zh':ZH,'epoch':epoch},ROOT/'best_checkpoint.pt')
  if epoch%10==0 or epoch==1:print(json.dumps(history[-1]),flush=True)
 net.load_state_dict(torch.load(ROOT/'best_checkpoint.pt',map_location='cpu',weights_only=True)['state_dict']);net.eval()
 torch.save({'state_dict':net.state_dict(),'labels':LABELS,'labels_zh':ZH,'epoch':best[1]},ROOT/'model_float.pt')
 with torch.no_grad():vl=net(vx)
 # Select reject thresholds on development validation only, never photo/test cases.
 choices=[]
 for p in [.4,.5,.6,.7,.8]:
  for m in [.05,.1,.2]:
   r=metrics(vl,vy,p,m);score=sum(r['per_class_recall'])/5;choices.append((score,p,m))
 _,pt,mt=max(choices)
 report=dict(architecture='Conv1-4, pool2, Conv4-8, pool2, Conv8-8, global average, Linear8-5',parameters=sum(p.numel() for p in net.parameters()),epochs_completed=epochs,best_epoch=best[1],device='cpu',torch_version=torch.__version__,elapsed_seconds=time.perf_counter()-start,labels=ZH,reject_probability=pt,reject_margin=mt,results={},raw_fpga_camera_test={'images':0,'accuracy':None},fpga_deployed=False,warning='Same-source drawing augmentation. Synthetic accuracy is not real-camera or unseen-expression accuracy.')
 for split,(a,b) in data.items():
  with torch.no_grad():logits=net(a)
  report['results'][split]=metrics(logits,b,pt,mt)
 # Frozen external diagnostic crops: manually rectified tablet crops from phone photos.
 # They are not the raw sensor stream and were not used for training/calibration/selection.
 photo_labels=[4,3,3,4,1,1,2,2,4];px=[]
 (ROOT/'photo_diagnostics').mkdir(exist_ok=True)
 for i,l in enumerate(photo_labels,1):
  src=INPUTROOT/f'photo_diagnostics/{i:02}_tablet_face.png'
  if not src.exists():src=PROJECT/f'cnn/reference/photo_checks/{i:02}_tablet_face.png'
  if src.resolve()!=(ROOT/'photo_diagnostics'/src.name).resolve():shutil.copy2(src,ROOT/'photo_diagnostics'/src.name)
  px.append(norm(np.array(Image.open(src).convert('L'))))
 with torch.no_grad():pl=net(torch.tensor(np.stack(px)[:,None]).float()/255)
 report['photo_diagnostic']=metrics(pl,torch.tensor(photo_labels),pt,mt)
 report['photo_diagnostic']['scope']='9 phone-photo tablet crops, manually rectified, same four drawing sources; no background examples; not raw FPGA camera or independent scene generalization.'
 export_quant(net,data,report,px,photo_labels)
 # Reload exactness check on held-out synthetic images.
 clone=Model();clone.load_state_dict(torch.load(ROOT/'model_float.pt',weights_only=True)['state_dict']);clone.eval()
 with torch.no_grad():assert torch.equal(net(data['synthetic_test'][0]),clone(data['synthetic_test'][0]))
 report['checkpoint_reload_exact']=True
 (ROOT/'history.json').write_text(json.dumps(history,indent=2),encoding='utf-8')
 (ROOT/'training_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
 print(json.dumps({k:v for k,v in report.items() if k!='results'},ensure_ascii=False,indent=2),flush=True)

def export_quant(net,data,report,photos,photo_labels):
 sd=net.state_dict();a=data['train'][0];exps=[-8];maxima=[]
 with torch.no_grad():
  for i in [0,3,6]:
   a=F.relu(F.conv2d(a,sd[f'features.{i}.weight'],sd[f'features.{i}.bias'],padding=1));ma=float(a.max());maxima.append(ma);exps.append(math.ceil(math.log2(max(ma,1e-6)/255)))
   if i!=6:a=F.max_pool2d(a,2)
 ws=[];bs=[];shifts=[]
 for l,i in enumerate([0,3,6]):
  ws.append(torch.round(sd[f'features.{i}.weight'].double()*128).clamp(-128,127));bs.append(torch.round(sd[f'features.{i}.bias'].double()/2**(exps[l]-7)));shifts.append(exps[l+1]-exps[l]+7)
 ws.append(torch.round(sd['classifier.weight'].double()*128).clamp(-128,127));bs.append(torch.round(sd['classifier.bias'].double()/2**(exps[3]-7)))
 assert min(shifts)>0
 weights=[int(v) for w in ws for v in w.flatten()];assert len(weights)==940
 (ROOT/'weights_int8.hex').write_text(''.join(f'{v&255:02x}\n' for v in weights+[0]*(1024-len(weights))),encoding='ascii')
 (ROOT/'quantization.json').write_text(json.dumps(dict(weight_count=940,weight_fraction_bits=7,activation_exponents=exps,shifts=shifts,biases=[b.to(torch.int64).tolist() for b in bs],calibration_split='train',calibration_maxima=maxima,activation_buffers_bytes=2048,weight_rom_depth=1024,rtl_integration_completed=False),indent=2),encoding='utf-8')
 def integer_forward(a):
  a=a.double()
  for l in range(3):
   a=F.conv2d(a,ws[l],bs[l],padding=1);a=torch.floor((a+2**(shifts[l]-1))/2**shifts[l]).clamp(0,255)
   if l<2:a=F.max_pool2d(a,2)
  return F.linear(torch.floor((a.sum((2,3))+32)/64),ws[3],bs[3])
 report['int8_check']={}
 for split in ['synthetic_validation','synthetic_test']:
  x,y=data[split];q=integer_forward(torch.from_numpy(np.load(ROOT/f'{split}.npz')['images'][:,None]))
  with torch.no_grad():fp=net(x)
  report['int8_check'][split]=dict(argmax_accuracy=float((q.argmax(1)==y).float().mean()),float_integer_argmax_agreement=float((q.argmax(1)==fp.argmax(1)).float().mean()),confusion_matrix=metrics(q,y)['confusion_matrix'])
 q=integer_forward(torch.tensor(np.stack(photos)[:,None]));report['int8_check']['photo_diagnostic']=metrics(q,torch.tensor(photo_labels))
 # Integer scores have their own scale; float rejection thresholds must not be applied to them.
 report['int8_check']['note']='Integer checks use argmax only. Hardware rejection thresholds and multi-class RTL remain to be implemented and validated.'

if __name__=='__main__':
 import argparse
 ap=argparse.ArgumentParser();ap.add_argument('--output-dir',type=Path);args=ap.parse_args()
 if args.output_dir:ROOT=args.output_dir.resolve();ROOT.mkdir(parents=True,exist_ok=True)
 main()

