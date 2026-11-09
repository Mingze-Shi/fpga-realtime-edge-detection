"""Actual supervised training. Reports synthetic metrics separately from camera accuracy."""
import argparse
import json
import random
import time
from pathlib import Path
import numpy as np
import torch
from torch import nn
from model import TinyExpressionCNN, LABELS, LABELS_ZH, specification

ROOT=Path(__file__).resolve().parent

def dataset(split):
    d=np.load(ROOT/'data'/f'{split}.npz')
    return torch.from_numpy(d['images'].copy()).unsqueeze(1).float()/255.,torch.from_numpy(d['labels'].copy())

@torch.no_grad()
def evaluate(net,x,y):
    net.eval();logits=net(x);loss=nn.functional.cross_entropy(logits,y).item()
    p=logits.argmax(1);cm=torch.zeros((len(LABELS),len(LABELS)),dtype=torch.int64)
    for a,b in zip(y.tolist(),p.tolist()):cm[a,b]+=1
    return {'loss':loss,'accuracy':(p==y).float().mean().item(),
            'confusion_matrix_rows_true_columns_predicted':cm.tolist()}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--epochs',type=int,default=200);ap.add_argument('--threads',type=int,default=4)
    args=ap.parse_args();torch.set_num_threads(args.threads)
    torch.manual_seed(20261030);random.seed(20261030);np.random.seed(20261030)
    out=ROOT/'runs'/'contrast_normalized';out.mkdir(parents=True,exist_ok=True)
    if (out/'model_float.pt').exists():raise SystemExit('Completed run exists; preserve it instead of overwriting.')
    train_x,train_y=dataset('train');val_x,val_y=dataset('synthetic_validation')
    stress=dataset('synthetic_stress') if (ROOT/'data/synthetic_stress.npz').exists() else None
    net=TinyExpressionCNN();opt=torch.optim.AdamW(net.parameters(),lr=.008,weight_decay=.0001)
    sched=torch.optim.lr_scheduler.CosineAnnealingLR(opt,T_max=args.epochs,eta_min=.0003)
    initial=evaluate(net,val_x,val_y);best=(-1.,float('inf'));history=[];start=time.perf_counter()
    for epoch in range(1,args.epochs+1):
        net.train();order=torch.randperm(len(train_y));total=correct=0;loss_sum=0.
        for idx in order.split(128):
            opt.zero_grad(set_to_none=True);logits=net(train_x[idx]);loss=nn.functional.cross_entropy(logits,train_y[idx])
            loss.backward();opt.step();total+=len(idx);loss_sum+=loss.item()*len(idx);correct+=(logits.argmax(1)==train_y[idx]).sum().item()
        sched.step();v=evaluate(net,val_x,val_y)
        row={'epoch':epoch,'train_loss':loss_sum/total,'train_accuracy':correct/total,'synthetic_validation':v}
        history.append(row)
        if v['accuracy']>best[0] or (v['accuracy']==best[0] and v['loss']<best[1]):
            best=(v['accuracy'],v['loss']);best_epoch=epoch
            torch.save({'state_dict':net.state_dict(),'model':specification(),'labels':LABELS,'labels_zh':LABELS_ZH,
                        'epoch':epoch,'training_data':'face ROI from one original Taffy drawing plus two generated camera simulations; three other expression drawings and invalid patches as negatives'},out/'best_checkpoint.pt')
        if epoch==1 or epoch%10==0:print(json.dumps({k:v for k,v in row.items() if k!='synthetic_validation'}|{'synthetic_val_accuracy':v['accuracy']},ensure_ascii=False),flush=True)
    checkpoint=torch.load(out/'best_checkpoint.pt',map_location='cpu',weights_only=True);net.load_state_dict(checkpoint['state_dict']);net.eval()
    torch.save(checkpoint,out/'model_float.pt')
    with torch.no_grad():
        actual=net(val_x[:8]);reloaded=TinyExpressionCNN();reloaded.load_state_dict(torch.load(out/'model_float.pt',weights_only=True)['state_dict']);reloaded.eval()
        assert torch.equal(actual,reloaded(val_x[:8])), 'Reloaded predictions changed'
    np.savez(out/'weights_float.npz',**{k:v.detach().numpy() for k,v in net.state_dict().items()})
    report={'model':specification(),'labels':LABELS_ZH,'epochs_completed':args.epochs,'best_epoch':best_epoch,
            'device':'cpu','torch':torch.__version__,'elapsed_seconds':time.perf_counter()-start,
            'initial_synthetic_validation':initial,'train':evaluate(net,train_x,train_y),
            'synthetic_validation':evaluate(net,val_x,val_y),'synthetic_stress':evaluate(net,*stress) if stress else None,
            'real_camera_test':{'images':0,'accuracy':None},'fpga_deployed':False,'quantization_validated':False,
            'checkpoint_reload_exact':True,'warning':'Same-source development validation. Photo diagnostics are evaluated separately after training and are not independent sensor-frame tests. No claim of FPGA readiness.'}
    (out/'history.json').write_text(json.dumps(history,ensure_ascii=False,indent=2),encoding='utf-8')
    (out/'training_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2),flush=True)

if __name__=='__main__':main()
