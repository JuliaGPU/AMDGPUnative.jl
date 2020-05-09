# AMDGPUnative API Reference

## Kernel launching

```@docs
@roc
AMDGPUnative.AbstractKernel
AMDGPUnative.rocfunction
```

## Device code API

### Thread indexing

#### CUDA terms

Use these functions for compatibility with CUDAnative.jl.

```@docs
threadIdx
blockIdx
blockDim
gridDim
```

#### OpenCL terms
```@docs
workitemIdx
workgroupIdx
workitemDim
workgroupDim
```

### Synchronization

```@docs
sync_workgroup
```

```@docs
AMDGPUnative.dynamic_rocfunction
```


