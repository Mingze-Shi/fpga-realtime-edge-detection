"""Verify label mapping, split integrity, saved model and int8 arithmetic."""
from pathlib import Path
import hashlib,json
import numpy as np
from numpy.lib.stride_tricks import sliding_window_view
import torch
from train import Model,LABELS
root=Path(__file__).resolve().parent;torch.set_num_threads(4)
mapping=json.loads((root/'labels.json').read_text(encoding='utf-8'))
assert [c['label'] for c in mapping['classes']]==LABELS
for item in mapping['mapping']:
 assert hashlib.sha256((root/item['source']).read_bytes()).hexdigest()==item['sha256']
seen=set();sets={}
for split,n in [('train',640),('synthetic_validation',160),('synthetic_test',160)]:
 d=np.load(root/f'{split}.npz');x,y=d['images'],d['labels'];assert x.shape==(n,32,32) and x.dtype==np.uint8
 assert np.bincount(y,minlength=5).tolist()==[n//5]*5
 for a in x:
  h=hashlib.sha256(a.tobytes()).hexdigest();assert h not in seen;seen.add(h)
 sets[split]=(x,y)
net=Model();net.load_state_dict(torch.load(root/'model_float.pt',map_location='cpu',weights_only=True)['state_dict']);net.eval();assert sum(p.numel() for p in net.parameters())==965
report=json.loads((root/'training_report.json').read_text(encoding='utf-8'))
for split,(x,y) in sets.items():
 with torch.no_grad():p=net(torch.tensor(x[:,None]).float()/255).softmax(1);v,i=p.topk(2,dim=1);out=i[:,0].clone();out[(v[:,0]<report['reject_probability'])|((v[:,0]-v[:,1])<report['reject_margin'])]=0
 assert out.tolist()==report['results'][split]['predictions']
# Independent NumPy int64 convolution oracle for quantized arithmetic.
q=json.loads((root/'quantization.json').read_text());w=np.array([int(s,16) for s in (root/'weights_int8.hex').read_text().split()],np.int64);w=np.where(w>=128,w-256,w)
shapes=[(4,1,3,3),(8,4,3,3),(8,8,3,3),(5,8)];ws=[];pos=0
for shape in shapes:
 n=int(np.prod(shape));ws.append(w[pos:pos+n].reshape(shape));pos+=n
assert pos==940 and len(w)==1024
x=sets['synthetic_test'][0][:10,None].astype(np.int64);a=x.copy();b=torch.tensor(x,dtype=torch.float64)
for l in range(3):
 windows=sliding_window_view(np.pad(a,((0,0),(0,0),(1,1),(1,1))),(3,3),axis=(2,3))
 a=np.einsum('ncyxij,ocij->noyx',windows,ws[l])+np.array(q['biases'][l])[None,:,None,None]
 a=np.clip((a+(1<<(q['shifts'][l]-1)))>>q['shifts'][l],0,255)
 b=torch.nn.functional.conv2d(b,torch.tensor(ws[l],dtype=torch.float64),torch.tensor(q['biases'][l],dtype=torch.float64),padding=1)
 b=torch.floor((b+2**(q['shifts'][l]-1))/2**q['shifts'][l]).clamp(0,255)
 if l<2:
  a=a.reshape(a.shape[0],a.shape[1],a.shape[2]//2,2,a.shape[3]//2,2).max((3,5));b=torch.nn.functional.max_pool2d(b,2)
 assert np.array_equal(a,b.numpy().astype(np.int64))
avg=(a.sum((2,3))+32)//64;logits=avg@ws[3].T+np.array(q['biases'][3])
ref=torch.nn.functional.linear(torch.floor((b.sum((2,3))+32)/64),torch.tensor(ws[3],dtype=torch.float64),torch.tensor(q['biases'][3],dtype=torch.float64))
assert np.array_equal(logits,ref.numpy().astype(np.int64))
result=dict(label_mapping_and_source_hashes=True,unique_input_arrays=len(seen),five_classes_balanced=True,saved_model_predictions_reproduced=True,int8_numpy_torch_exact_cases=10,fpga_rtl_checked=False)
(root/'verification.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result,indent=2))
