"""Small image classifier prototype; this file is not an FPGA implementation."""
import torch
from torch import nn

LABELS = ['other', 'taffy_reference']
LABELS_ZH = ['其他或无效画面', '原始塔菲图案']

class TinyExpressionCNN(nn.Module):
    def __init__(self):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv2d(1, 4, 3, padding=1), nn.ReLU(), nn.MaxPool2d(2),
            nn.Conv2d(4, 8, 3, padding=1), nn.ReLU(), nn.MaxPool2d(2),
            nn.Conv2d(8, 8, 3, padding=1), nn.ReLU(),
            nn.AdaptiveAvgPool2d(1),
        )
        self.classifier = nn.Linear(8, len(LABELS))

    def forward(self, x):
        return self.classifier(self.features(x).flatten(1))

def specification():
    net = TinyExpressionCNN()
    return {'input_shape': [1, 1, 32, 32],
            'input': '32x32 face ROI; integer min-max normalization with range<16 gate, then divided by 255',
            'layers': 'conv3x3(1,4)-relu-pool2-conv3x3(4,8)-relu-pool2-conv3x3(8,8)-relu-global_average-linear(8,2)',
            'parameters': sum(p.numel() for p in net.parameters()),
            'fpga_synthesis_completed': False,
            'camera_accuracy_measured': False}
