require "requirement"

class CudnnRequirement < Requirement
  fatal true

  def initialize(tags)
    @version = tags.shift if /\d+\.*\d*/ === tags.first
    super
  end

  satisfy :build_env => false do
    next false unless nvcc_path = which("nvcc")
    next true unless @version

    cuda_lib_path = nvcc_path.dirname.parent/"lib"
    if OS.mac?
      cudnn_path = cuda_lib_path/"libcudnn.dylib"
      cudnn_version ||= cudnn_path.readlink.to_s.match(/(\d)\.dylib/)[1]
    else  # OS.linux?
      cudnn_path = cuda_lib_path/"libcudnn.so"
      cudnn_version ||= cudnn_path.readlink.to_s.match(/\.so\.?(\d)/)[1]
    end
    Version.new(cudnn_version.to_s) >= Version.new(@version)
  end

  def message
    cuda_version = /\d\.\d/.match(Utils.popen_read("nvcc", "-V")).to_s
    cuda_dir = which("nvcc").dirname.parent.to_s
    if @version
      s = "cuDNN #{@version} or later is required."
    else
      s = "cuDNN is required."
    end
    s += <<-EOS.undent
      To use this formula with NVIDIA graphics cards you will need to
      download and install the cuDNN library from nvidia.com.

          https://developer.nvidia.com/cudnn

      Complete the free registration and the survey behind the 'Download'
      button. Download the latest cuDNN library for CUDA #{cuda_version}, and
      unpack the include/ and lib/ directories in the CUDA installation path,
      which is below.

          #{cuda_dir}

    EOS
    s += super
    s
  end

  def inspect
    "#<#{self.class.name}: #{name.inspect} #{tags.inspect} version=#{@version.inspect}>"
  end
end
