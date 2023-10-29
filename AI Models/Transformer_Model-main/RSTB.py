import torch 
import torch.nn as nn
import STL

device = 'cpu'
class RSTB(nn.Module):
    """Implementation of the Residual Swin Transformer Layer"""
    
    def __init__(self, dim, n, heads, window_size, device=device):
        """Inputs:
        - dim: The dimension of the input feature image
        - n: No. of STL layers in between
        - heads : Array of attention heads in MSA
        - window_size : Window size of the MSA"""
        super().__init__()
        self.layers={}
        self.n = n
        for i in range(n):
            self.layers[i+1] = STL.swin(dim= dim, heads = heads[i], window_size=window_size, device=device).to(device=device)
        self.convolution = nn.Conv2d(in_channels = dim[0], out_channels=dim[0], kernel_size = 3, padding = "same").to(device=device)
        
    def forward(self, input_features):
        """Forward function of RSTB"""
        N, C, H, W = input_features.shape
        x = input_features
        for i in range(self.n):
            x = self.layers[i+1](x)
        return input_features + self.convolution(x)
        