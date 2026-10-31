// kernel
__global__ void add(int n, float *x) {
  int i = threadIdx.x;
  if (i < n) x[i] += 1.0f;
}
