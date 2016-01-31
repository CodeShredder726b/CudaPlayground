#include <cuda.h>
#include <common.h>
#include <cpu_anim.h>

#define DIM 1024
#define SPEED 0.25f
#define PI 3.1415926535897932f
#define MAX_TEMP 1.0f
#define MIN_TEMP 0.0001f

struct DataBlock
{
	unsigned char* output_bitmap;
	float* dev_inSrc;
	float* dev_outSrc;
	float* dev_constSrc;
	CPUAnimBitmap* bitmap;
	cudaEvent_t start, stop;
	float totalTime;
	float frames;
};

__global__ void copy_const_kernel(float* iptr, const float* cptr)
{
	int x = threadIdx.x + blockIdx.x * blockDim.x;
	int y = threadIdx.y + blockIdx.y * blockDim.y;
	int offset = x + y * blockDim.x *gridDim.x;

	if(cptr[offset] != 0)
	{
		iptr[offset] = cptr[offset];
	}
}

__global__ void blend_kernel(float* outSrc, const float* inSrc)
{
	int x = threadIdx.x + blockIdx.x * blockDim.x;
	int y = threadIdx.y + blockIdx.y * blockDim.y;
	int offset = x + y * blockDim.x *gridDim.x;

	int left = offset - 1;
	int right = offset + 1;
	if(x == 0)
	{
		left++;
	}
	if(x == (DIM - 1))
	{
		right--;
	}

	int top = offset - DIM;
	int bottom = offset + DIM;
	if(y == 0)
	{
		top += DIM;
	}
	if(y == (DIM - 1))
	{
		bottom -= DIM;
	}

	outSrc[offset] = inSrc[offset] + SPEED * (inSrc[top] + inSrc[bottom] + inSrc[left] + inSrc[right] - inSrc[offset]*4);
}

void anim_gpu(DataBlock* data, int ticks)
{
	HANDLE_ERROR(cudaEventRecord(data->start, 0));
	dim3 blocks(DIM/16, DIM/16);
	dim3 threads(16,16);
	CPUAnimBitmap* bitmap = data->bitmap;

	for(int i = 0; i < 90; i++)
	{
		copy_const_kernel<<<blocks,threads>>>(data->dev_inSrc, data->dev_constSrc);
		blend_kernel<<<blocks,threads>>>(data->dev_outSrc, data->dev_inSrc);
		swap(data->dev_inSrc, data->dev_outSrc);
	}

	float_to_color<<<blocks,threads>>>(data->output_bitmap, data->dev_inSrc);

	HANDLE_ERROR(cudaMemcpy(bitmap->get_ptr(), data->output_bitmap, bitmap->image_size(), cudaMemcpyDeviceToHost));
	HANDLE_ERROR(cudaEventRecord(data->stop, 0));
	HANDLE_ERROR(cudaEventSynchronize(data->stop));
	float elapsedTime;
	HANDLE_ERROR(cudaEventElapsedTime(&elapsedTime, data->start, data->stop));
	data->totalTime += elapsedTime;
	++data->frames;
	printf("Average Time per Frame: %3.1f ms\n", data->totalTime/data->frames);
}

void anim_exit(DataBlock* data)
{
	cudaFree(data->dev_inSrc);
	cudaFree(data->dev_outSrc);
	cudaFree(data->dev_constSrc);

	HANDLE_ERROR(cudaEventDestroy(data->start));
	HANDLE_ERROR(cudaEventDestroy(data->stop));
}

int main(void)
{
	DataBlock data;
	CPUAnimBitmap bitmap(DIM, DIM, &data);
	data.bitmap = &bitmap;
	data.totalTime = 0;
	data.frames = 0;
	HANDLE_ERROR(cudaEventCreate(&data.start));
	HANDLE_ERROR(cudaEventCreate(&data.stop));

	HANDLE_ERROR(cudaMalloc((void**)&data.output_bitmap, bitmap.image_size()));
	HANDLE_ERROR(cudaMalloc((void**)&data.dev_inSrc, bitmap.image_size()));
	HANDLE_ERROR(cudaMalloc((void**)&data.dev_outSrc, bitmap.image_size()));
	HANDLE_ERROR(cudaMalloc((void**)&data.dev_constSrc, bitmap.image_size()));

	float* temp = (float*)malloc(bitmap.image_size());
	for(int i = 0; i < DIM*DIM; i++)
	{
		temp[i] = 0;
		int x = i % DIM;
		int y = i / DIM;
		if((x > 300) && (x < 600) && (y > 310) && (y < 601))
		{
			temp[i] = MAX_TEMP;
		}
	}
	temp[DIM*100+100] = (MAX_TEMP + MIN_TEMP) / 2;
	temp[DIM*700+100] = MIN_TEMP;
	temp[DIM*300+300] = MIN_TEMP;
	temp[DIM*200+700] = MIN_TEMP;
	for(int y = 800; y < 900; y++)
	{
		for(int x = 400; x < 500; x++)
		{
			temp[x+y*DIM] = MIN_TEMP;
		}
	}
	HANDLE_ERROR(cudaMemcpy(data.dev_constSrc, temp, bitmap.image_size(), cudaMemcpyHostToDevice));
	for(int y = 800; y < DIM; y++)
	{
		for(int x = 0; x < 200; x++)
		{
			temp[x+y*DIM] = MAX_TEMP;
		}
	}
	HANDLE_ERROR(cudaMemcpy(data.dev_inSrc, temp, bitmap.image_size(), cudaMemcpyHostToDevice));
	free(temp);
	bitmap.anim_and_exit((void(*)(void*,int))anim_gpu, (void(*)(void*))anim_exit);
}