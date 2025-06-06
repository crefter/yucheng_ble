#pragma once
#include "QRSDet.h"
#include "ECGDisp.h"

// Module reset
extern void resetECGAlg();

// Main function for ECG detection
extern short ECGAnaly(int ecgdata);

// ECG Display processing
extern void getECGDisp(int *ecgdisp);

// Output
extern void getECGResult(int *qrstype, int *qrsdelay, short *hr, short *rr, short *hrv);
extern void getFinalResult(short *hr, int *qrstype, bool *afflag);

extern void get5ParamResult(float *heavy_load, float *pressure, float *HRV_norm, float *body,
                            float *sympathetic_parasympathetic, unsigned char *respiratory_rate);

//ECG preprocessing
int ECGPreProcess(int data);
bool ECGConvert(int *ecgdata, int *outdata, bool init);
