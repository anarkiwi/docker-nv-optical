"""OpenCV CUDA checks that need a GPU: NVIDIA Optical Flow 2.0 and cudacodec.

Usage: gpu_optical.py VIDEO, where VIDEO is a 60 frame 1280x720 HEVC stream.
"""

import sys
import unittest

import cv2
import numpy as np

VIDEO = ""
SHIFT = (5, -3)


def textured_frame(size, seed=0):
    """Smoothed uniform noise: dense texture the flow estimator can lock onto."""
    rng = np.random.default_rng(seed)
    noise = rng.integers(0, 256, size=(size[1], size[0]), dtype=np.uint8)
    return cv2.GaussianBlur(noise, (0, 0), 1.5)


class Device(unittest.TestCase):
    """A CUDA device is visible to OpenCV."""

    def test_device(self):
        self.assertGreaterEqual(cv2.cuda.getCudaEnabledDeviceCount(), 1)
        info = cv2.cuda.DeviceInfo(0)
        cv2.cuda.printShortCudaDeviceInfo(0)
        self.assertGreaterEqual(info.majorVersion(), 7)
        self.assertTrue(info.isCompatible())


class NvidiaOpticalFlow(unittest.TestCase):
    """NvidiaOpticalFlow_2_0 recovers a known global translation."""

    def test_translation(self):
        size = (640, 480)
        first = textured_frame(size)
        second = np.roll(first, shift=(SHIFT[1], SHIFT[0]), axis=(0, 1))
        nvof = cv2.cuda.NvidiaOpticalFlow_2_0.create(size)
        try:
            flow, _ = nvof.calc(cv2.cuda.GpuMat(first), cv2.cuda.GpuMat(second), None)
            grid = nvof.getGridSize()
            dense = np.empty((size[1] // grid, size[0] // grid, 2), np.float32)
            dense = nvof.convertToFloat(flow.download(), dense)
        finally:
            nvof.collectGarbage()
        margin = 32 // grid
        interior = dense[margin:-margin, margin:-margin].reshape(-1, 2)
        median = np.median(interior, axis=0)
        inliers = np.mean(np.all(np.abs(interior - SHIFT) < 0.5, axis=1))
        print(f"grid {grid} median flow {median.tolist()} inliers {inliers:.3f}")
        np.testing.assert_allclose(median, SHIFT, atol=0.25)
        self.assertGreater(inliers, 0.9)


class CudaCodec(unittest.TestCase):
    """cudacodec decodes a file into GPU memory with NVDEC."""

    def test_reader(self):
        reader = cv2.cudacodec.createVideoReader(VIDEO)
        frames = 0
        shape = None
        while True:
            ok, frame = reader.nextFrame()
            if not ok:
                break
            frames += 1
            shape = frame.size()
        print(f"cudacodec decoded {frames} frames of {shape}")
        self.assertEqual(frames, 60)
        self.assertEqual(shape, (1280, 720))


if __name__ == "__main__":
    VIDEO = sys.argv.pop(1)
    unittest.main(verbosity=2)
