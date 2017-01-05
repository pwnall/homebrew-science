require File.expand_path("../Requirements/cuda_requirement", __FILE__)

class Cudainfo < Formula
  desc "CLI tool that shows the properties of installed CUDA GPUs"
  homepage "https://github.com/pwnall/cudainfo"

  stable do
    url "https://github.com/pwnall/cudainfo/archive/v0.9.tar.gz"
    sha256 "bf58ca69df86d9b7ff4948fd5fda249410c7ee0677fb2bef6664f8b0399b33fc"
  end

  head do
    url "https://github.com/pwnall/cudainfo.git"
  end

  depends_on CudaRequirement

  def install
    system "make", "cudainfo"
    bin.install "cudainfo"
  end

  test do
    cuda_info = YAML.load Utils.popen_read("cudainfo")
    assert !cuda_info.empty?
  end
end
