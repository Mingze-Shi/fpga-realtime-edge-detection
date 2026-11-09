"""Export the existing trained CNN to deterministic int8 RTL parameters."""
import sys, json, math, hashlib
from pathlib import Path
import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'cnn/reference'
sys.path.insert(0,str(SOURCE))
from model import TinyExpressionCNN
from preprocess import input_array
torch.set_num_threads(4)
net=TinyExpressionCNN()
net.load_state_dict(torch.load(ROOT/'cnn/model_float.pt',map_location='cpu',weights_only=True)['state_dict'])
net.eval()
sd=net.state_dict()
cases=[]
for line in (SOURCE/'data/manifest.jsonl').read_text(encoding='utf-8').splitlines():
    row=json.loads(line)
    cases.append((row['path'].replace('/','_'),np.array(Image.open(SOURCE/row['path']).convert('L')),row['label'],row['split']))
for i,p in enumerate(sorted((SOURCE/'photo_checks').glob('*_tablet_face.png'))):
    cases.append((p.stem,input_array(Image.open(p)),int(i in (0,3,8)),'photo_development'))
xs=torch.tensor(np.stack([c[1] for c in cases])[:,None],dtype=torch.float64)/255
exps=[-8]; maxima=[]
with torch.no_grad():
    a=xs.float()
    for idx in (0,3,6):
        a=F.relu(F.conv2d(a,sd[f'features.{idx}.weight'],sd[f'features.{idx}.bias'],padding=1))
        maxima.append(float(a.max()))
        exps.append(math.ceil(math.log2(float(a.max())/255)))
        if idx!=6:a=F.max_pool2d(a,2)
weights=[];biases=[];shifts=[];qws=[];qbs=[]
for l,idx in enumerate((0,3,6)):
    w=torch.round(sd[f'features.{idx}.weight'].double()*128).clamp(-128,127)
    b=torch.round(sd[f'features.{idx}.bias'].double()/2**(exps[l]-7))
    qws.append(w);qbs.append(b);weights.extend(w.to(torch.int8).flatten().tolist());biases.append(b.to(torch.int64).tolist())
    shifts.append(exps[l+1]-exps[l]+7)
w=torch.round(sd['classifier.weight'].double()*128).clamp(-128,127)
b=torch.round(sd['classifier.bias'].double()/2**(exps[3]-7))
weights.extend(w.to(torch.int8).flatten().tolist());biases.append(b.to(torch.int64).tolist())

def integer_forward(arr):
    a=torch.tensor(arr.copy(),dtype=torch.float64)[None,None];layers=[]
    for l in range(3):
        a=F.conv2d(a,qws[l],qbs[l],padding=1)
        a=torch.floor((a+2**(shifts[l]-1))/2**shifts[l]).clamp(0,255)
        if l<2:a=F.max_pool2d(a,2)
        layers.append(a.to(torch.int64).flatten().tolist())
    avg=torch.floor((a.sum((2,3))+32)/64)
    logits=F.linear(avg,w,b)[0].to(torch.int64).tolist()
    return layers,avg.to(torch.int64).flatten().tolist(),logits

out=ROOT/'assets/cnn';out.mkdir(parents=True,exist_ok=True)
(out/'weights.hex').write_text(''.join(f'{v&255:02x}\n' for v in weights+[0]*(1024-len(weights))),encoding='ascii')
vh=['// Generated from cnn/model_float.pt. Signed int8 weights, uint8 activations.',
    'function signed [31:0] cnn_bias;', ' input [1:0] layer; input [3:0] channel;', ' begin cnn_bias=0; case ({layer,channel})']
for l,bs in enumerate(biases):
    for c,v in enumerate(bs):vh.append(f"6'd{16*l+c}: cnn_bias=32'sh{int(v)&0xffffffff:08x};")
vh+=['default: cnn_bias=0; endcase end endfunction']
for l,s in enumerate(shifts):vh.append(f'localparam integer CNN_SHIFT{l+1}={s};')
(ROOT/'rtl/cnn_params.vh').write_text('\n'.join(vh)+'\n',encoding='ascii')
vectors=ROOT/'tests/cnn_vectors';vectors.mkdir(exist_ok=True)
report=[]
for i,(name,arr,label,split) in enumerate(cases):
    layers,avg,logits=integer_forward(arr)
    with torch.no_grad():fl=net(torch.tensor(arr.copy()).float()[None,None]/255)[0].tolist()
    for suffix,values in [('input',arr.flatten()),('pool1',layers[0]),('pool2',layers[1]),('conv3',layers[2]),('avg',avg)]:
        (vectors/f'{i:02}_{suffix}.hex').write_text(''.join(f'{int(v):02x}\n' for v in values),encoding='ascii')
    report.append(dict(index=i,name=name,label=label,split=split,logits=logits,predicted=int(logits[1]>logits[0]),float_logits=fl,float_predicted=int(fl[1]>fl[0])))
# Deterministic non-image cases exercise saturation, padding, extreme inputs.
rng=np.random.default_rng(20261030)
for j,arr in enumerate([np.zeros((32,32),np.uint8),np.full((32,32),255,np.uint8),rng.integers(0,256,(32,32),dtype=np.uint8)],len(cases)):
    layers,avg,logits=integer_forward(arr)
    for suffix,values in [('input',arr.flatten()),('pool1',layers[0]),('pool2',layers[1]),('conv3',layers[2]),('avg',avg)]:
        (vectors/f'{j:02}_{suffix}.hex').write_text(''.join(f'{int(v):02x}\n' for v in values),encoding='ascii')
    report.append(dict(index=j,name='arithmetic_stress',label=None,logits=logits,predicted=int(logits[1]>logits[0])))
(vectors/'expected_logits.hex').write_text(''.join(f'{v&0xffffffff:08x}\n' for r in report for v in r['logits']),encoding='ascii')
model=dict(architecture='32x32x1 Conv1-4 pool2 Conv4-8 pool2 Conv8-8 GAP Linear8-2',parameters=938,
    weights_int8=len(weights),weight_fraction_bits=7,activation_exponents=exps,requantization_right_shifts=shifts,
    calibration_maxima=maxima,biases_int32=biases,case_count=len(report),cases=report,
    labeled_cases=sum(r.get('label') is not None for r in report),
    correct=sum(r.get('label')==r['predicted'] for r in report if r.get('label') is not None),
    agreement_with_float=sum(r['predicted']==r['float_predicted'] for r in report if 'float_predicted' in r),
    float_comparison_cases=len(cases),model_sha256=hashlib.sha256((ROOT/'cnn/model_float.pt').read_bytes()).hexdigest(),
    independent_camera_test=False,training_this_export=False)
(out/'model.json').write_text(json.dumps(model,ensure_ascii=False,indent=2),encoding='utf-8')
raw=(cases[0][1].astype(np.uint16)*150//255+40).astype(np.uint8)
span=int(raw.max())-int(raw.min())
normalized=((raw.astype(np.int32)-int(raw.min()))*255+span//2)//span
_,_,cl=integer_forward(normalized.astype(np.uint8))
(vectors/'capture_raw.hex').write_text(''.join(f'{int(v):02x}\n' for v in raw.flatten()),encoding='ascii')
(vectors/'capture_normalized.hex').write_text(''.join(f'{int(v):02x}\n' for v in normalized.flatten()),encoding='ascii')
(vectors/'capture_logits.hex').write_text(''.join(f'{int(v)&0xffffffff:08x}\n' for v in cl),encoding='ascii')
print(json.dumps({k:v for k,v in model.items() if k not in ('cases','biases_int32')},indent=2))
