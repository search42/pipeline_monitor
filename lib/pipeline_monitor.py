#coding=utf-8
import sys,os,time,re
import ConfigParser
import inspect
import copy
import glob
import pdb
from warnings import warn
from optparse import OptionParser,OptionGroup
import commands
class pipeline_monitor(object):
	def __init__(self):
		self.tasks={}                                                                  #{label:[[jobids,out.file,error.file],...]}
		self.config={}                                                                 #键值对<=congfig 文件
		self.ncpus=1
		self.mem ="10M"
		self.host=None
		self.param_qsub=['ncpus','mem','host']
	def prase_config(self,file):
		"""
		self.config<= {key:value}
		"""
		config = ConfigParser.ConfigParser()                                           #使用ConfigParser解析config文件
		config.optionxform = str
		config.read(file)
		for section in config.sections():
			key_value=config.items(section)
			intersection=set(self.config.keys()).intersection(zip(*key_value)[0])
			if len(intersection)>0:
				warn("config file %s: \nhas repeat key:%s"%(file,intersection))
			self.config.update(key_value)                                              #value中不能有'"字符


	def process_pipeline(self,file_pipe,mode="run"):
		"""
		mode [run, check]
		"""
		assert mode in ["run","check"]
		#param_check_pipe_var={}
		errs_checked=0
		commands=self.prase_pipeline(file_pipe)                                                                             #解析pipeline中,得到命令及参数
		for cmd,parameter in commands:                                                                                      #命令逐条进行操作
			label      =parameter.get("Label",None)
			if mode=="check":
				try:
					param_seted  =self._process_parameter(p_tmp=parameter,p=self.config,label=label,check=1)
				except:
					pdb.set_trace()
				param_require=re.findall(r"%\((\S+?)\)s",cmd)
				param_omit   =set(param_require).difference(param_seted.keys())
				if param_omit:
					errs_checked+=1
					warn("%s parameter is omited: %s"%("[%s]"%label if label else "cmd:[%s]"%cmd,list(param_omit) ) )
				if parameter.get("qsub","no")=="exec":
					variates =re.findall(r"global\s*(\S+)",cmd)
					if variates:
						#warn("Warning... BLACK TECH global variate %s"%variates)
						for var in variates:
							if var in dir():
								warn("%s BLACK TECH global parameter [%s] will overwrite namespace"%("[%s]"%label if label else '',var) )
							exec "global %s ; %s=''"%(var,var)
			else:
				require_job=parameter.get("require_job",None)
				workpath   =parameter.get("workpath",self.config['outdir'])                                             #workpath,前后覆盖
				if self.check_done(workpath,label):                                                                     #如任务之前做过，则跳过
					pass
				else:
					self.monitor(labels=require_job,job_ids=[])                                                                    #等待依赖步骤执行完毕
					sys.stdout.write("[%s] start... %s\n"%(label,time.strftime("%Y-%m-%d %H:%M:%S") ) )
					self.run_cmd(cmd,self.config,parameter)                                                             #执行命令
		if errs_checked:
			sys.exit("Sorry, please check parameter seted !!!")
		return 0

	def prase_pipeline(self,file):
		"""
		[ [cmd1,parameter1],[cmd2,parameter2]]
		type(parameter1)==type({})
		"""
		cmds=[]                                                                        #[cmd,parameter]
		fr=open(file)
		for (idx0,cmd_pipe) in enumerate(fr.read().split("\n#") ):                     #以单个行首#对代码分段
			parameter={}                                                               #{ncpus:1,mem:3g,interpreter:python,...]
			mark_multi_line=0
			for (idx1,cmd_pipe_line) in enumerate(cmd_pipe.split("\n") ):              #逐行读取
				m=re.search(r"^```(\S+)?(\s+[^#]+)?",cmd_pipe_line)                     #m.group(1)=>[python,''] m.group(2)=>[key=value key2=value2 ...]
				if m:                                                                  #```=>命令块标示符
					mark_multi_line+=1                                                 #遍历到```的次数
					if mark_multi_line==2:                                              #读到第二个```，命令块结束
						mark_multi_line=0
						#cmds.append([cmd,parameter])
						yield [cmd,parameter]                                          #parameter: pipe->#命令行（```更新，其它行继承；然而，label=None,qsub=no默认）
						parameter.update({'qsub':'no','Label':None})
						continue
					cmd=''                                                             #清空cmd变量
				if idx1==0 or (m and mark_multi_line==1):                              # 参数行:'#'开头或```开头，则读取参数
					if idx0==0 and idx1==0 and mark_multi_line!=1 :                    #pipe第一行特殊
						if not re.search(r"^#",cmd_pipe_line):                         #不以#开头，则第一行当作命令行
							cmd=self._string_to_expression(cmd_pipe_line)
							#cmds.append([cmd,parameter])
							yield [cmd,parameter]
							parameter.update({'qsub':'no','Label':None})
							continue
						else:                                                          #去掉行首#
							cmd_pipe_line=re.sub(r"^#",'',cmd_pipe_line)
					parameter.update(self._prase_key_value(cmd_pipe_line%self.config) )
					if mark_multi_line==1:                                             #对于```命令块，多一个interpreter参数
						parameter['interpreter']=m.group(1)
				else:                                                                  #命令行
					if mark_multi_line==1:                                             #对于```命令块的处理
						cmd+=self._string_to_expression(cmd_pipe_line) + "\n"
					else:                                                              #对于#命令行的处理
						cmd=self._string_to_expression(cmd_pipe_line)
						if re.search(r"^\s*(#.*)?$",cmd):continue
						yield [cmd,parameter]
						parameter.update({'qsub':'no','Label':None})
		#return cmds                                                                   #返回 [[cmd1,parameter1],[cmd2,parameter2]]
	def _prase_key_value(self,string):
		"""
		a=1 b=2 e = 3 d=4 # e=5   =>{a:1,b:2,d:4}
		"""
		h={}
		m=re.search(r"^([^#]*)",string)
		for item in m.group(1).split():
			item_pairs=item.split("=")
			if len(item_pairs)<2: continue
			h.update([item_pairs])
		return h
	def _string_to_expression(self,string,status=0):                                   #解决部分可变参数
		newcmd=string
		if re.search(r"^\s*['\"]",string):
			try:
				newcmd=eval(string)
			except(NameError):                                                         #参数在前边命令未运行时，变量未定义，暂不
				newcmd=string
				warn("String_to_expression NameError in string: {%r}"%(string) )
		return newcmd

	def add_opt(self,opt,addto=None):                                                  #在字典中加入新的key<=>value
		"""
		opt: {key:value} or [(key,value)]
		"""
		if addto==None:
			addto=self.config
		addto.update(opt)

	def _inspect_class(self,obj):                                                      #内省，得到属性<=>值
		h={}
		attributes = inspect.getmembers(obj, lambda a:not(inspect.isroutine(a)))
		tmp=[a for a in attributes if not(a[0].startswith('__') and a[0].endswith('__'))]
		h.update(tmp)
		return h
	def _process_parameter(self,p_tmp=None,p=None,label=None,check=0):
		"""
		p_default,p_tmp,p==>'Default parameter','Pipeline parameter','Config_File parameter'
		check =[0,1,2] 检查参数重写：0 不检；1只检config 与pipeline,2全检
		"""
		parameter={}
		parameter.update([i for i in self._inspect_class(self).items() if i[0] in self.param_qsub])
		explain=['Default parameter','Pipeline parameter','Config_File parameter']
		for idx,param in enumerate([p_tmp,p]):
			intersection=set(parameter.keys()).intersection(param.keys())
			if check and len(intersection)>0:
				if check==1 and idx==0:
					pass
				else:
					warn("%s {%s} overwrite {%s} in %s"%("[%s]"%label if label else '',explain[idx+1],explain[idx],list(intersection) ) )
			parameter.update(param)
		return parameter
	def run_cmd(self,cmd,param={},param_tmp={}):                                                  #以qusb/exec/sh运行命令cmd,实现对流程参数的配置
		parameter=self._process_parameter(param_tmp,param)                                        #优先级：程序default<pipe<config
		qsub       =parameter.get("qsub","no")
		label      =parameter.get("Label",None)
		interpreter=parameter.get("interpreter",None)
		workpath   =parameter.get("workpath",parameter['outdir'])
		if not os.path.exists(workpath):os.makedirs(workpath) 
		os.chdir(workpath)
		if qsub == "yes" or (qsub=="no" and interpreter == "python"):                             #将cmd写到脚本中
			if label==None:
				warn("must has label value for command: {%s}"%cmd)                                #最好每步都有label，便于查错，断点开始任务
				exit(1)
			scriptname = "run_" + label + "."+ str(int(time.time()*10)%1000000) + (".py" if interpreter == "python" else ".sh")
			fw=open(scriptname,"w")
			cmd+="\nprint '' \nprint '==[OK]==' \n" if interpreter == "python" else "\necho '' \necho '==[OK]==' \n"     #添加==[OK]==标志到.oxxx文件，作为任务完成标志
			fw.write(cmd%parameter)
			fw.close()
			if qsub == "yes":
				cmd="qsub -V -d ./ %s %s"%(scriptname," ".join( ["-l %s=%s"%(i,parameter[i]) for i in self.param_qsub if parameter.get(i,None)] ) )
			else:
				cmd="python scriptname"
		if qsub == "exec":
			try:
				exec cmd%parameter
			except:
				warn("Failed!!!,check the commands in exec: {%s}"%(cmd%parameter) )
		elif qsub in ['no','yet','yes']:
			cmd=re.sub(r"""#[^#'"\n]*$""","",cmd)
			status,output=commands.getstatusoutput(cmd.strip()%parameter)
			if qsub in ['yet','yes']:
				job_ids=[]
				for line in output.split("\n"):
					m=re.search(r"^your job (\d+)|^(\d+\S+)|Job ID is : (\d\S+)\.",line,re.I)     #目前三种模式
					if m:
						jobid=[m.group(i) for i in range(1,4) if m.group(i) != None]
						job_ids.extend(jobid)
				if len(job_ids)==0:
					warn("Cann't get job id from command: {%s}"%(cmd%parameter) )
				for id in job_ids:
					self.tasks.setdefault(label,[]).append( self._qsub_job_out_err(id) )          #用于检错
			if status != 0: 
				warn("Failed!!!,check the commands: {%s}"%(cmd%parameter) )                       #非正常退出，报警
		return 0

	def _qsub_job_out_err(self,jobid):
		status,output=commands.getstatusoutput('qstat -f %s'%jobid)                                                             #查找任务标准/错误输出
		err,out='',''
		infos=output.split("\n")
		for idx,line in enumerate(infos):
			for idx2 in range(idx+1,len(infos) ):                                                                               #针对value有多行的情况
				line2=infos[idx2]
				if not re.search(r"=",line2):
					line=line.strip() + line2.strip()
				else:
					break
			m=re.search(r"(Error_Path|Output_Path) = .*?:?(/\S+)",line)
			if m:
				if m.group(1) == 'Error_Path' :err=m.group(2)
				if m.group(1) == 'Output_Path':out=m.group(2)
		return [jobid,out,err]

	def monitor(self,labels=None,job_ids=[]):                                                                                   #labels与job_ids二选一
		if len(job_ids)==0 and labels==None or len(labels)==0:
			return 0
		if type(labels)==type(''):
			if labels=="All":                                                                                                   #All 代表所有label
				labels=self.tasks.keys()
			else:
				labels=labels.split(",")
		for label in labels:
			if self.tasks.has_key(label):
				job_ids.extend( zip(*self.tasks[label])[0])

		if type(job_ids)==type(''):
			job_ids=job_ids.split(",")
		id_check={}.fromkeys(job_ids)                                                                                           #check
		while 1:
			mark=0
			status,output=commands.getstatusoutput("qstat")                                                                     #捕获当前节点上的任务
			for line in output.split("\n"):
				m=re.search(r"^\s*(\d+\S*)",line)
				if m and id_check.has_key(m.group(1)):
					mark+=1                                                                                                     #多少任务还需等待
			if mark==0:
				break
			time.sleep(5)
		return 0

	def check_done(self,path,label):
		if label==None:
			return 0
		files=[i for i in glob.glob("%s/run_%s*.o*"%(path,label) ) if re.search(r"\.o(\d+)?$",i)]
		files_e=[i for i in glob.glob("%s/run_%s*.e*"%(path,label) ) if re.search(r"\.e(\d+)?$",i)]
		if len(files)>1:
			warn("[Is task done?] Check , in label: [%s] too many OUTPUT files  \n{%s}"%(label,files) )
		elif len(files)==0:
			return 0
		status,info_tail=commands.getstatusoutput("tail -1 %s"%files[0])                                                        #.e在.exx前
		if status != 0: 
			warn("Failed!!!,when checking the output of label: [%s]"%(label) )                                                  #非正常退出，报警
		if info_tail=="==[OK]==":                                                                                               # 成功运行标志==[OK]==
			err_ignore="\nCan't find file \S+\.pid\nYou'll have to kill the Xvnc process manually\n\n"
			for f_err in files_e:
				if os.path.getsize(f_err):                          
					if 90<=os.path.getsize(f_err)<=100 and re.search(err_ignore,file(f_err).read()):
						pass
					else:
						warn("Plese check the err file,there may be an error:%s"%files_e[0])
			return 1
		return 0

	def check_error(self,labels):
		if labels=='All':
			labels= self.tasks.keys() 
		elif type(labels)==type(''):
			labels=labels.split(',')
		files_e=[]
		err_ignore="\nCan't find file \S+\.pid\nYou'll have to kill the Xvnc process manually\n\n"
		time.sleep(5)
		for label in labels:
			realerr=[re.sub(r"\d+$","",i) if os.path.exists(re.sub(r"\d+$","",i) ) else i for i in zip(*self.tasks[label] )[2] ]  #如有.e文件，不用.exxx
			try:
				files_e.extend([k for k in realerr if (os.path.getsize(k) and (os.path.getsize(k)!=96 or not re.search(err_ignore,file(k).read() ) ) )])   #.e文件不为空，或为err_ignore
			except:
				#pdb.set_trace() why?? ./lib/pipeline_monitor.py:291: UserWarning: check there ['', '/data/BIN/zhangsch/project/pipeline_monitor/test/test1/1.3/...
				warn("check there %s"%realerr)   #pdb.set_trace()
		if len(files_e)>0:
			warn("Plese check the err file,there may be an error:\n%s"%("\n".join(files_e) ) )

def main():
	usage = "usage: %prog [options] pipeline" 
	description = "Contact: search42 <search42zh@gmail.com>"
	parser = OptionParser(usage,version="%prog 1.0.3",description = description)
	Common_group = OptionGroup(parser,'Common Options')
	Common_group.add_option('-f',dest='config',help='config file for pipeline',metavar='FILE',type='string',default=None)
	Common_group.add_option('-o',dest="outdir",help='outdir of flow, default=./',metavar='DIR',type='string',default="./")
	parser.add_option_group(Common_group)

	(options, args) = parser.parse_args()
	if len(args) <= 0:
		parser.print_help()
		exit(1)
	start_time=time.time()
	sys.stdout.write("[Pipe] start... %s\n"%time.strftime("%Y-%m-%d %H:%M:%S"))
	pipeline=pipeline_monitor()
	pipeline.prase_config(options.config)
	pipeline.add_opt( [ ('outdir',os.path.abspath(options.outdir) ),('config',os.path.abspath(options.config) ) ] )                                                        #添加额外参数到self.config
	sys.stdout.write("[Check_parameter] start... %s\n"%time.strftime("%Y-%m-%d %H:%M:%S") )
	pipeline.process_pipeline(args[0],mode="check")                                                                            #检查参数
	pipeline.process_pipeline(args[0])
	pipeline.check_error("All")                                                                                                #检查所有带label命令可能的错误
	sys.stdout.write("[END] completed... %s\n"%(time.strftime("%Y-%m-%d %H:%M:%S")))
	sys.stdout.write("Time consumed %.3f seconds\n"%(time.time()-start_time) )
	return 0

if __name__ == "__main__":
	main()
