`自动化` `任务断点续做` `查错`

# 1.概述 #
实现[**流程自动化**]，[**断点续做**]，[**查错**] 功能。运行方式如下：
```
$ run_pipeline
```
    
    Usage: run_pipeline [options] pipeline

    Contact: search42 <search42zh@gmail.com>
    
    Options:
      --version   show program's version number and exit
      -h, --help  show this help message and exit

    Common Options:
      -f FILE   config file for pipeline
      -o DIR    outdir of flow, default=./

程序需指定输出目录*outdir*,另需要*2个文件*：

1. [格式化的流程脚本](https://github.com/search42/pipeline_monitor/blob/master/test/test_pipe_parameter.txt)
    - 配置运行方式**qsub** 可选 [*yes, yet, no, exec* ]

        * yes 表示当前命令以qsub进行投递到torque队列中，用计算节点计算，可对资源 ncpus， mem， host使用进行控制,默认ncpus=1， mem=10M
        * yet 表示命令中已包含qsub/Doqsub命令.  #对此在[断点续做]的支持不好
        * no  表示当前命令在当前节点用shell直接运行；如任务时间长，内存、cpu需求量大，请用以上两种方式运行; **default=no**
        * exec 则在当前python中运行，可很好地实现参数的定制化； #注：在中，若无python标记，则会先写进脚本中，然后再运行 exec "python 脚本",参数定制功能会受影响

    - 命令的标签**Label**，用以区分命令及log文件run_{Lable}*sh[.][e,o][number];default=None；若为None，则[断点续做] [查错]功能会受影响
    
    - 输出目录**workpath**; default='上一命令的workpath' or 'outdir'

2. [参数配置文件](https://github.com/search42/pipeline_monitor/blob/master/test/test_config.txt)
  以 *key*=*value* 的形式指定流程中的参数；可以**[group]**来对参数进行分组。

总的结果会输出在**outdir**下，每步的结果在**workpath**中。

# 2.输入文件展示 #

```
##################################################################
##格式化的流程脚本(因与markdown标记重合，故在以下用`` `表示三个连续的`）
##################################################################
#Label=a.1 qsub=yes [yes,no,yet] ncpus=1 mem=2G workpath=%(outdir)s/1.1 #host=               #通过行首#对下行命令的运行参数进行定制,qusb到集群
echo command1.1 %(c1)s && sleep 10
#Label=a.2 qsub=yet      [yet] ncpus=1 mem=2G workpath=%(outdir)s/1.2 #host=                 #以commands调用,并获取job id
Doqsub "echo command1.2 %(c1)s && sleep 20"
     #

`` ` Label=a.3 qsub=yet      [yet] ncpus=1 mem=2G workpath=%(outdir)s/1.3 #host=              #支持多任务投递
for i in {1..5};do echo echo command1.3.${i} %(c1)s >test1.3.${i}.sh;done
ls test1.3*sh |while read i;do Doqsub ${i};done
`` `

#Label=b qsub=no  [yes,no,yet] ncpus=1 mem=2G workpath=%(outdir)s/2 #host=                   #以commands调用,commands.getstatusoutput
echo command2 %(c2)s

`` ` Label=c qsub=yes [yes,no,yet] ncpus=1 mem=2G  workpath=%(outdir)s/3                      #`` `为#的多行形式，`` `之后未紧跟python等字样，则使用sh解释器
"echo command3.1 %s "%( "ta" if 1<0 else 'zsc')                                              #command3 %s 为可修改的命令,sh执行;%s 不能与%(c3)s同时出现
echo command3.2 %(c3)s
`` `

`` `python Label=d qsub=exec  [yes,no,yet,exec] ncpus=1 mem=3G workpath=%(outdir)s/4          #以python 执行,暂不支持其它语言
  #comand4             #在```内#不能在行首
global test_string     #为后面的命令传参
if len('%(outdir)s') >5:
  print "length of outdir gt 5 %(c4)s"
  test_string="{C4} length of outdir gt 5 %(c4)s"               
else:
  print "ength of outdir lt 5 %(c5)s"
  test_string="{C4} length of outdir lt 5 %(c4)s"
`` `

#Label=e qsub=yes [yes,no,yet] ncpus=1 mem=1G workpath=%(outdir)s/5 require_job=a.1,a.2,b,c,d  #等待a.1,a.2,b,c,d任务执行完毕，才会执行此命令
"echo command5 %s "%(test_string) + "%(c5)s"                                                   #若同时使用%s 、%(c5)s两种格式化方法，可用+分开,test_string为上一步的值
```

```
###############################################################
##config 文件
###############################################################
[common_param]
c1=COMMAND1
c2=COMMAND2
c3=COMMAND3
c4=COMMAND4
c5=COMMAND5
```

# 3. 测试 #


to install:
```
$ git clone https://github.com/search42/pipeline_monitor.git
$ cd pipeline_monitor
$ python setup.py build
$ python setup.py install
```
to test:
```
$ run_pipeline  -f test_config.txt -o test_out/ test_pipe_parameter.txt
```

    [Pipe] start... 2016-09-19 14:03:12
    [a.1] start... 2016-09-19 14:03:12
    [a.2] start... 2016-09-19 14:03:12
    [a.3] start... 2016-09-19 14:03:12
    [b] start... 2016-09-19 14:03:14
    [c] start... 2016-09-19 14:03:14
    [d] start... 2016-09-19 14:03:14
    length of outdir gt 5 COMMAND4
    [e] start... 2016-09-19 14:03:39
    [END] completed... 2016-09-19 14:03:44
    Time consumed 31.8602759838 seconds



# 4. 测试结果 #

```
$ tree
```
    test_out/
    ├── 1.1
    │   ├── run_a.1.649924.sh
    │   ├── run_a.1.649924.sh.e59520
    │   └── run_a.1.649924.sh.o59520
    ├── 1.2
    │   ├── run.649927.sh
    │   ├── run.649927.sh.e
    │   ├── run.649927.sh.e59521
    │   ├── run.649927.sh.o
    │   └── run.649927.sh.o59521
    ├── 1.3
    │   ├── run.649929.sh
    │   ├── run.649932.sh
    │   ├── run.649934.sh
    │   ├── run.649936.sh
    │   ├── run.649939.sh
    │   ├── test1.3.1.sh
    │   ├── test1.3.1.sh.e
    │   ├── test1.3.1.sh.e59522
    │   ├── test1.3.1.sh.o
    │   ├── test1.3.1.sh.o59522
    │   ├── test1.3.2.sh
    │   ├── test1.3.2.sh.e
    │   ├── test1.3.2.sh.e59523
    │   ├── test1.3.2.sh.o
    │   ├── test1.3.2.sh.o59523
    │   ├── test1.3.3.sh
    │   ├── test1.3.3.sh.e
    │   ├── test1.3.3.sh.e59524
    │   ├── test1.3.3.sh.o
    │   ├── test1.3.3.sh.o59524
    │   ├── test1.3.4.sh
    │   ├── test1.3.4.sh.e
    │   ├── test1.3.4.sh.e59525
    │   ├── test1.3.4.sh.o
    │   ├── test1.3.4.sh.o59525
    │   ├── test1.3.5.sh
    │   ├── test1.3.5.sh.e
    │   ├── test1.3.5.sh.e59526
    │   ├── test1.3.5.sh.o
    │   └── test1.3.5.sh.o59526
    ├── 2
    ├── 3
    │   ├── run_c.649940.sh
    │   ├── run_c.649940.sh.e59527
    │   └── run_c.649940.sh.o59527
    ├── 4
    └── 5
        ├── run_e.650192.sh
        ├── run_e.650192.sh.e59528
        └── run_e.650192.sh.o59528
