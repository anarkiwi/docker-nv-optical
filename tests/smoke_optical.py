"""GPU-free checks of the OpenCV build in the optical image."""

import os
import sys
import tempfile
import unittest

import cv2
import numpy as np


def build_info():
    """Return the `key: value` lines of cv2.getBuildInformation() in order."""
    fields = []
    for line in cv2.getBuildInformation().splitlines():
        key, sep, value = line.strip().partition(":")
        if sep:
            fields.append((key.strip(), value.strip()))
    return fields


class BuildInformation(unittest.TestCase):
    """cv2.getBuildInformation() reports the expected features."""

    @classmethod
    def setUpClass(cls):
        cls.info = build_info()

    def field(self, key):
        """Value of the first `key:` line."""
        for name, value in self.info:
            if name == key:
                return value
        raise AssertionError(f"{key} not in build information")

    def test_cuda(self):
        cuda = self.field("NVIDIA CUDA")
        self.assertTrue(cuda.startswith("YES"), cuda)
        for feature in ("CUFFT", "CUBLAS", "NVCUVID", "NVCUVENC"):
            self.assertIn(feature, cuda)
        arches = self.field("NVIDIA GPU arch").split()
        expected = os.environ.get("EXPECT_CUDA_ARCH_BIN", "").replace(".", "").split()
        self.assertTrue(arches)
        for arch in expected:
            self.assertIn(arch, arches)

    def test_modules(self):
        built = self.field("To be built").split()
        for module in (
            "cudaoptflow",
            "cudacodec",
            "cudaarithm",
            "cudaimgproc",
            "cudawarping",
            "cudev",
            "videoio",
            "python3",
        ):
            self.assertIn(module, built)

    def test_ffmpeg(self):
        self.assertTrue(self.field("FFMPEG").startswith("YES"))
        for lib in ("avcodec", "avformat", "avutil", "swscale"):
            self.assertRegex(self.field(lib), r"YES \(\d+\.\d+\.\d+\)")

    def test_python(self):
        interpreter = self.field("Interpreter")
        self.assertIn(sys.prefix, interpreter)
        self.assertIn(np.__version__, self.field("numpy"))

    def test_no_nonfree(self):
        self.assertEqual(self.field("Non-free algorithms"), "NO")


class Bindings(unittest.TestCase):
    """The CUDA classes the image exists for are exposed to Python."""

    def test_optical_flow(self):
        self.assertTrue(hasattr(cv2.cuda, "NvidiaOpticalFlow_2_0"))
        self.assertTrue(hasattr(cv2.cuda.NvidiaOpticalFlow_2_0, "create"))
        self.assertTrue(hasattr(cv2.cuda, "FarnebackOpticalFlow"))

    def test_cudacodec(self):
        for name in ("createVideoReader", "createVideoWriter"):
            self.assertTrue(hasattr(cv2.cudacodec, name), name)

    def test_gpumat(self):
        self.assertTrue(hasattr(cv2.cuda, "GpuMat"))


class Linkage(unittest.TestCase):
    """Installed libraries resolve driver libraries through the loader path only."""

    def test_no_stub_paths(self):
        roots = [os.path.dirname(cv2.__file__), "/usr/local/lib"]
        libraries = [
            os.path.join(root, name)
            for top in roots
            for root, _, names in os.walk(top)
            for name in names
            if ".so" in name and not os.path.islink(os.path.join(root, name))
        ]
        self.assertTrue(libraries)
        for library in libraries:
            with open(library, "rb") as handle:
                self.assertNotIn(b"/opt/nvstubs", handle.read(), library)


class VideoIO(unittest.TestCase):
    """videoio round-trips frames through the bundled ffmpeg."""

    def test_ffmpeg_backend(self):
        self.assertTrue(cv2.videoio_registry.hasBackend(cv2.CAP_FFMPEG))

    def test_round_trip(self):
        size, count = (160, 120), 10
        ramp = np.arange(size[0], dtype=np.uint8)
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "ramp.mkv")
            writer = cv2.VideoWriter(
                path, cv2.CAP_FFMPEG, cv2.VideoWriter_fourcc(*"FFV1"), 25, size
            )
            self.assertTrue(writer.isOpened())
            frames = [
                np.dstack([np.broadcast_to(ramp + i, size[::-1])] * 3)
                for i in range(count)
            ]
            for frame in frames:
                writer.write(np.ascontiguousarray(frame))
            writer.release()
            reader = cv2.VideoCapture(path, cv2.CAP_FFMPEG)
            decoded = []
            while True:
                ok, frame = reader.read()
                if not ok:
                    break
                decoded.append(frame)
            reader.release()
        self.assertEqual(len(decoded), count)
        for got, want in zip(decoded, frames):
            np.testing.assert_allclose(got, want, atol=2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
