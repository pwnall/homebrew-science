require "yaml"

require File.expand_path("../Requirements/cuda_requirement", __FILE__)
require File.expand_path("../Requirements/cudnn_requirement", __FILE__)

class Tensorflow < Formula
  desc "Software library for Machine Intelligence"
  homepage "https://www.tensorflow.org/"

  stable do
    # TODO: Wait for the next Tensorflow release to ship the formula.
    # 0.12.1 won't work because of at least 2 bugs that got fixed on master.
    url "https://github.com/tensorflow/tensorflow/archive/0.12.1.tar.gz"
    sha256 "799a0029d95a072d2f12ecdcc5add5082a4c278074fa060741e1634f593ca7bc"
  end

  head do
    url "https://github.com/tensorflow/tensorflow.git"

    patch do
      # AVX2+ hosts get compilation errors without this patch.
      # See https://github.com/tensorflow/tensorflow/issues/6558
      url "https://github.com/tensorflow/tensorflow/pull/6723.patch"
      sha256 "63a9059b9c584087dc979579f5899317fda1086241a3a944afff19143d757b45"
    end
  end

  option "with-build-parallelism", "Enable parallel build (RAM-intensive)"
  option "with-cuda", "Build with CUDA v7.0+ support"
  option "with-gcp", "Build with Google Cloud Platform support"
  option "with-hdfs", "Build with HDFS support"
  option "with-opencl", "Build with OpenCL support"

  needs :cxx11

  depends_on "bazel" => :build
  depends_on CudaRequirement if build.with? "cuda"
  depends_on CudnnRequirement if build.with? "cuda"
  depends_on "coreutils" => :build if build.with? "cuda"
  depends_on "curl" => :optional
  depends_on "eigen"
  depends_on "gcc" => :optional if build.with? "cuda"
  depends_on "giflib"
  depends_on "jsoncpp"
  depends_on "hadoop" if build.with? "hdfs"
  depends_on "jpeg"
  depends_on "libpng"
  # The line below assumes the newer LLVM formula that includes clang.
  # For older LLVM formulas, the dependency should be "llvm" => ["with-clang"].
  depends_on "llvm" if build.with? "opencl"
  depends_on "nasm"
  depends_on "pcre"
  depends_on "protobuf"
  depends_on :python => :recommended
  depends_on :python3 => :optional
  depends_on "swig" => :build
  depends_on "homebrew/dupes/zlib" => :optional
  depends_on "homebrew/science/cudainfo" => :build if build.with? "cuda"

  with_python = build.with?("python") || build.with?("python3")
  pythons = build.with?("python3") ? ["with-python3"] : []
  depends_on "homebrew/python/numpy" => [:recommended] + pythons if with_python

  def install
    args = ["--compilation_mode=opt"]
    ENV["PYTHON_BIN_PATH"] = which "python"
    ENV["USE_DEFAULT_PYTHON_LIB_PATH"] = "1"

    if build.with? "cuda"
      args << "--config=cuda"
      ENV["TF_NEED_CUDA"] = "1"

      ENV["CUDA_TOOLKIT_PATH"] ||= which("nvcc").dirname.parent
      # Filter out superenv's gcc shim.
      ENV["GCC_HOST_COMPILER_PATH"] ||= which_all("gcc").reject do |bin|
        bin.to_s.include?("shims/super/gcc")
      end.first
      ENV["TF_CUDA_VERSION"] ||= /\d\.\d/.match(Utils.popen_read("nvcc", "-V")).to_s

      ENV["CUDNN_INSTALL_PATH"] ||= ENV["CUDA_TOOLKIT_PATH"]
      if OS.mac?
        cudnn_path = Pathname.new(ENV["CUDNN_INSTALL_PATH"])/"lib"/"libcudnn.dylib"
        ENV["TF_CUDNN_VERSION"] ||= cudnn_path.readlink.to_s.match(/(\d)\.dylib/)[1]
      else # OS.linux?
        cudnn_path = Pathname.new(ENV["CUDNN_INSTALL_PATH"])/"lib"/"libcudnn.so"
        ENV["TF_CUDNN_VERSION"] ||= cudnn_path.readlink.to_s.match(/\.so\.?(\d)/)[1]
      end

      cuda_info = YAML.load Utils.popen_read("cudainfo")
      ENV["TF_CUDA_COMPUTE_CAPABILITIES"] ||= cuda_info.map { |gpu| gpu["compute_version"] }.uniq.sort.join(",")
    else
      ENV["TF_NEED_CUDA"] = "0"
    end

    if build.with? "opencl"
      args << "--config=sycl"
      ENV["TF_NEED_OPENCL"] = "1"

      # Filter out superenv's clang shims.
      ENV["HOST_CXX_COMPILER"] = which_all("clang++").reject do |bin|
        bin.to_s.include?("shims/super/clang++")
      end.first
      ENV["HOST_C_COMPILER"] = which_all("clang").reject do |bin|
        bin.to_s.include?("shims/super/clang")
      end.first

      # TODO: computeCpp does not currently have a Mac OS release.
      # When that happens, follow the CUDA approach above to get library paths.
      ENV["COMPUTECPP_TOOLKIT_PATH"] = "/usr/local/computecpp"
      ENV["SYCL_RT_LIB_PATH"] = "lib/libComputeCpp.dylib"
    else
      ENV["TF_NEED_OPENCL"] = "0"
    end

    if build.with? "gcp"
      ENV["TF_NEED_GCP"] = "1"
    else
      ENV["TF_NEED_GCP"] = "0"
    end

    if build.with? "hdfs"
      ENV["TF_NEED_HDFS"] = "1"
    else
      ENV["TF_NEED_HDFS"] = "0"
    end

    if build.without? "build-parallelism"
      args << "--jobs=1"
    end

    # Optimize for the host's CPU, unless building a bottle.
    args << "--copt=-march=native" unless build.bottle?

    args << "//tensorflow:libtensorflow.so"
    args << "//tensorflow:libtensorflow_c.so"
    args << "//tensorflow:libtensorflow_cc.so"
    args << "//tensorflow/tools/pip_package:build_pip_package" if build.with? "python"

    system "./configure"
    system "bazel", "build", *args

    if build.with? "python"
      system "./bazel-bin/tensorflow/tools/pip_package/build_pip_package", buildpath/"tmp"
      wheel_path = Dir.glob(buildpath/"tmp/tensorflow*.whl").first
      Language::Python.each_python(build) do |python, version|
        ENV.prepend_create_path "PYTHONPATH", lib+"python#{version}/site-packages"
        system python, "-m", "pip", "install", wheel_path
      end
    end

    # Tensorflow's headers are peppered throughout the source directory.
    # The C API only needs one file: tensorflow/c/c_api.h
    # However, using the C++ shared library may require all the headers.
    Dir.glob("tensorflow/**/*.h").each do |header|
      header_dir = File.dirname header
      include_dir = include/header_dir
      include_dir.mkpath
      include_dir.install header
    end

    lib.install "bazel-bin/tensorflow/libtensorflow.so"
    lib.install "bazel-bin/tensorflow/libtensorflow_c.so"
    lib.install "bazel-bin/tensorflow/libtensorflow_cc.so"
  end

  test do
    (testpath/"tf-test.cc").write <<-'EOS'
// Tensorflow test that adds two vectors.

#include <tensorflow/c/c_api.h>

#include <cstdlib>
#include <iostream>

void checkStatus(TF_Status *status, const char *methodName) {
  if (TF_GetCode(status) != TF_OK) {
    std::cerr << methodName << " error: " << TF_Message(status) << '\n';
    exit(1);
  }
}

int main() {
  TF_Status *status = TF_NewStatus();

  TF_Graph *graph = TF_NewGraph();

  TF_OperationDescription *feed1Description =
      TF_NewOperation(graph, "Placeholder", "feed1");
  TF_SetAttrType(feed1Description, "dtype", TF_FLOAT);
  TF_Operation *feed1 = TF_FinishOperation(feed1Description, status);
  checkStatus(status, "TF_FinishOperation");

  TF_OperationDescription *feed2Description =
      TF_NewOperation(graph, "Placeholder", "feed2");
  TF_SetAttrType(feed2Description, "dtype", TF_FLOAT);
  TF_Operation *feed2 = TF_FinishOperation(feed2Description, status);
  checkStatus(status, "TF_FinishOperation");

  TF_OperationDescription *sumDescription =
      TF_NewOperation(graph, "Add", "sum");
  TF_Output feed1Output = {feed1, 0};
  TF_AddInput(sumDescription, feed1Output);
  TF_Output feed2Output = {feed2, 0};
  TF_AddInput(sumDescription, feed2Output);
  TF_Operation *sum = TF_FinishOperation(sumDescription, status);
  checkStatus(status, "TF_FinishOperation");

  float term1[] = {1.0, 42.0};
  float term2[] = {2.0, 2.0};
  int64_t inputDimensions[] = {2};

  TF_Tensor *tensor1 =
      TF_AllocateTensor(TF_FLOAT, inputDimensions, 1, sizeof(term1));
  std::memcpy(TF_TensorData(tensor1), term1, sizeof(term1));

  TF_Tensor *tensor2 =
      TF_AllocateTensor(TF_FLOAT, inputDimensions, 1, sizeof(term2));
  std::memcpy(TF_TensorData(tensor2), term2, sizeof(term2));

  TF_SessionOptions *sessionOptions = TF_NewSessionOptions();
  TF_Session *session = TF_NewSession(graph, sessionOptions, status);

  const TF_Output inputs[] = {
      {feed1, 0}, {feed2, 0},
  };
  TF_Tensor *inputValues[] = {tensor1, tensor2};
  const TF_Output outputs[] = {
      {sum, 0},
  };
  const TF_Operation *targetOperations[] = {sum};
  TF_Tensor *outputValues[1] = {nullptr};
  TF_SessionRun(session, nullptr, inputs, inputValues, 2, outputs, outputValues,
                1, targetOperations, 1, nullptr, status);
  checkStatus(status, "TF_SessionRun");

  TF_Tensor *result = outputValues[0];
  if (TF_TensorType(result) != TF_FLOAT) {
    std::cerr << "Unexpected output tensor type." << '\n';
    return 1;
  }
  if (TF_NumDims(result) != 1) {
    std::cerr << "Unexpected output tensor dimension count." << '\n';
    return 1;
  }

  float *data = static_cast<float *>(TF_TensorData(result));
  int64_t elementCount = TF_Dim(result, 0);
  for (int64_t i = 0; i < elementCount; ++i) {
    std::cout << data[i] << ' ';
  }
  std::cout << '\n';

  return 0;
}
EOS
    system ENV.cxx, "-ltensorflow_c", "-o", "tf-test", "tf-test.cc"
    assert_equal "3 44", Utils.popen_read("./tf-test").strip
  end
end
