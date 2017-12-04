#!/usr/bin/env python
# -*- coding: UTF-8 -*-
"""
just for call pipeline_monitor 
"""
import sys

from setuptools import find_packages, setup  ## 采用setuptools，使用egg 

#from setuptools.extension import Extension

## 下面这2个变量会被调用
package_list = ["pipeline_monitor"]           ## 指定要安装的package 的名字
package_dir  = {"pipeline_monitor": "lib"}   ## 该名字对应的源文件的相对路径，当前文件夹下的rslib 文件夹
scripts      = ['scripts/run_pipeline',"scripts/Doqsub"]

"""
# 用于C 代码扩展，编译成C的动态库，这里我用了ctypes 模块在mutilstats 中做了C 扩展
extensions = [
		Extension("rslib.permutation.cal_permutation", # 会编译成 rslib/permutation/cal_permutation.so 
			["rslib/permutation/sr_msort.c",           # 下面这里的为C 的source code 路径
				"rslib/permutation/cal_permutation.c", # 可以用language 参数指定语言
				]),
		]
"""
if __name__ == "__main__":
	setup(
			name                = "pipeline_monitor",             # package 名称
			version             = "1.0.3",             # 版本号，每次git tag 前，都要先修改版本号
			description         = "pipeline automatic",             # 描述package 功能
			long_description    = __doc__,             # package 简介
			author              = "search42",
			author_email        = "search42zh@gmail.com",
			license             = "MIT",               # license 名称
			platforms           = ["Linux","Mac OS-X","UNIX"],                # 支持的平台
			url                 = "https://github.com/search42/pipeline_monitor",  # url 地址
			packages            = package_list,                               # 14行 定义的变量
			package_dir         = package_dir,                                # 15行 定义的变量
			scripts             = scripts,
			#data_files          = ['test/test_config.txt','test_pipe_parameter.txt'],                                         # 包需要带的数据文件
			#ext_modules         = extensions,                                 # 扩展，见22行
			setup_requires      = ['numpy >= 1.9.2']                         # build 时需要环境满足的依赖包，setuptools 会自动检查
			
			## 若除了库文件之外，还带着可执行的脚本，如 cnvkit ，内含命令行调用的接口，可把它放在当前路径，scripts文件夹下 
			## 用 scripts = ['scripts/cnvkit'], 来指定即可，安装时，若python 当前安装的prefix 为/opt, 则scripts 会自动安装到/opt/bin下，而package会安装到/opt/lib/pythonX.X/site-packages/ 下
			)


