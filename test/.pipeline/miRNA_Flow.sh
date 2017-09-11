##################################################################
##格式化的流程脚本
##################################################################
mkdir rawdata  report  result database
#Label=0.prepare.data workpath=%(outdir)s/rawdata
ln -s %(Rawdatadir)s/{*,*/*}.gz .
``` Label=0.prepare.hairpin.species qsub=yes workpath=%(outdir)s/database
if [ "%(Species)s" = "None" ];then
  python /home/rongzhengqin/developing/dev/microRNA/s1_process2harpin.py %(MiRHairpin)s > all.hairpin.fa
  python  /home/rongzhengqin/developing/dev/microRNA/s1_process2merge_mature.py %(MiRMature)s  %(MiRHairpin)s   > all.mature.fa
else
  python /home/rongzhengqin/pipe/miRseq/prepare_seq.py  %(MiRHairpin)s %(Species)s 1 %(Species)s_hairpin
  python /home/rongzhengqin/pipe/miRseq/prepare_seq.py  %(MiRHairpin)s %(Species)s 0 no_%(Species)s_hairpin
  python /home/rongzhengqin/pipe/miRseq/prepare_seq.py  %(MiRMature)s %(Species)s 1 %(Species)s_mature
  python /home/rongzhengqin/pipe/miRseq/prepare_seq.py  %(MiRMature)s %(Species)s 0 no_%(Species)s_mature 
fi
perl -pwe 's/^(>\S+).*/$1/' %(Genome)s > $(basename %(Genome)s)
ln -s %(GTF)s .
/home/rongzhengqin/bin/getseq_region_ongene  --region=protein --genome=%(Genome)s --outfmt=fasta --outprefix=%(Species)s --infmt=gtf $(basename %(GTF)s)
/home/rongzhengqin/bin/getseq_region_ongene  --region=utr3 --genome=%(Genome)s --outfmt=fasta --outprefix=%(Species)s --infmt=gtf $(basename %(GTF)s)
/home/rongzhengqin/bin/getseq_region_ongene  --region=mrna --genome=%(Genome)s --outfmt=fasta --outprefix=%(Species)s --infmt=gtf $(basename %(GTF)s)
```
``` Label=0.prepare.anno.pep qsub=yes workpath=%(outdir)s/database
if [ %(BlastKO_Result)s = None ]; then
gffread %(GTF)s -x known.cds.fa  -g %(Genome)s
/data/tools/trinityrnaseq-2.2.0/TransDecoder-3.0.0/TransDecoder.LongOrfs -t known.cds.fa -S 
/data/tools/trinityrnaseq-2.2.0/TransDecoder-3.0.0/TransDecoder.Predict -t known.cds.fa  --single_best_orf
python /data/BIN/suzhencheng/bin/extract_transdecoder_revise.py known.cds.fa.transdecoder.pep
mkdir temp_anno;cd temp_anno
perl /data/BIN/zhangsch/project/RNA/scripts/split_fasta_by_order.pl ../known.cds.fa.transdecoder.pep.sel.fa 10 leaf
 #Doqsub -t 16 -s run_%(Label)s_go "/data/tools/interproscan-5.15-54.0/interproscan.sh -appl PfamA,TIGRFAM,SMART,SuperFamily,PRINTS -dp -f tsv,html --goterms  --iprlookup -t p -i known.novel.pep.fa"
for i in leaf.? ; do Doqsub -t 16 -s run_%(Label)s_go "/data/tools/interproscan-5.15-54.0/interproscan.sh -appl PfamA,TIGRFAM,SMART,SuperFamily,PRINTS -dp -f tsv,html --goterms  --iprlookup -t p -i ${i}" ;done
 #(根据物种信息选择)
 #Doqsub -t 16 -s run_%(Label)s_kegg "mkdir kegg; blastp -query known.novel.pep.fa -num_threads 23 -db %(BlastKO_DB)s  -outfmt 6  -max_target_seqs 1 -evalue 0.00001 -out kegg/blast.ko.xls"
for i in leaf.? ; do Doqsub -t 16 -s run_%(Label)s_kegg "blastp -query ${i} -num_threads 23 -db %(BlastKO_DB)s  -outfmt 6  -max_target_seqs 1 -evalue 0.00001 -out blast.ko.${i}.xls" ;done
fi
```
###workpath=%(outdir)s/result
##mkdir 0.info/ 1.QC/ 2.preprocess/ 3.mapping/ 4.norm/ 5.snqc/ 6.diff 7.target 8.target_func 
#Label=0.prepare.sampleinfo workpath=%(outdir)s/result/0.info
cp %(SampleInfo)s sampleinfo.xls

``` Label=1.QC.fastqc qsub=yet workpath=%(outdir)s/result 
/home/rongzhengqin/bin/fqQC/fastqQC --run-fastqc --seqlen=%(SeqenceLen)s --outdir=1.QC --indir=../rawdata 0.info/sampleinfo.xls
ls *fastqc.sh | while read i; do mv ${i} run_%(Label)s_${i} ;Doqsub -t 4 -m 2G  run_%(Label)s_${i};done 
```
``` Label=1.QC.stats qsub=yet workpath=%(outdir)s/result require_job=1.QC.fastqc
cd ../rawdata && ls *.zip  | while read i; do unzip $i; done && cd  -
Doqsub -s run_%(Label)s "/home/rongzhengqin/bin/fqQC/fastqQC --run-stat --seqlen=%(SeqenceLen)s --outdir=1.QC --indir=../rawdata --qual=%(Quality)s 0.info/sampleinfo.xls"
```
``` Label=2.preprocess.removeadpter qsub=yet workpath=%(outdir)s/result/2.preprocess
 #echo mkfifo $(echo $i|cut -f2).fq \&\& gunzip ../../rawdata/$(echo $i|cut -f2) >$(echo $i|cut -f2).fq \&\
grep -v "^#" %(SampleInfo)s | while read i; do echo perl /data/BIN/zhangsch/project/RNA/lib/miRNA/preprocess.pl -i ../../rawdata/$(echo $i|cut -f2 -d" ") -d $(echo $i|cut -f1 -d" ") -a %(Adapter5)s -b %(Adapter3)s >run_%(Label)s_$(echo $i|cut -f1 -d" ").sh;done
ls run_%(Label)s*sh |while read i;do Doqsub -t1 -m4G $i;done
```
#Label=2.preprocess.collapsed.fa qsub=yes  workpath=%(outdir)s/result/2.preprocess require_job=2.preprocess.removeadpter
grep -v "^#" %(SampleInfo)s |cut -f1 |while read i;do perl -anwe 'print ">%(Species)s_${.}_x$F[1]\\n$F[2]\\n"' $i/clean.txt >$i/$i.collapsed.fa ;done

# Label=2.preprocess.Rfam.blast qsub=yet workpath=%(outdir)s/result/2.preprocess require_job=2.preprocess.collapsed.fa
grep -v "^#" %(SampleInfo)s |cut -f1 | while read i; do Doqsub -t4 -m 2G -s run_%(Label)s.$i "blastn -task blastn-short  -query $i/$i.collapsed.fa -db /data/database/Rfam/Rfam_microRNA/mir_Rfam  -outfmt 6  -max_target_seqs 1 -out $i/$i.collapsed.fa.Rfamanno -evalue 0.01 -num_threads 4 ";done

``` Label=2.preprocess.Rfam.filterReads qsub=yes workpath=%(outdir)s/result/2.preprocess require_job=2.preprocess.Rfam.blast
python /data/BIN/zhangsch/project/RNA/lib/miRNA/Rfam_filter.py %(SampleInfo)s ./
python /home/rongzhengqin/pipe/miRseq/len_plot.py %(SampleInfo)s
```

#Label=3.mapping.index qsub=yes  ncpus=2 mem=10G workpath=%(outdir)s/result
"echo 1 > /dev/null %s "%("||" if self.config.get("GenomeBOWT1index") else "&&") + "mkdir $(dirname %(Genome)s)/bowtie_index && bowtie-build %(Genome)s  $(dirname %(Genome)s)/bowtie_index/$(basename %(Genome)s)"

``` Label=3.mapping.align ncpus=1 mem=2G qsub=yes workpath=%(outdir)s/result/3.mapping require_job=3.mapping.index
'/home/rongzhengqin/pipe/miRseq/stat_miRseq -t 8 --indir=../2.preprocess/ --outdir=./  -D %s'%(self.config.get('GenomeBOWT1index') if self.config.get('GenomeBOWT1index') else "$(dirname %(Genome)s)/bowtie_index/$(basename %(Genome)s)" ) + " %(SampleInfo)s"
python /home/rongzhengqin/scripts/mergetables.py *.txt miRseq_stat.mapping.xls 
ls *.arf | while read i; do /home/rongzhengqin/pipe/miRseq/arf_parse_mappings.pl $i -c 26 > $i.microRNA.26 ;done 
ls *.arf | while read i; do /home/rongzhengqin/pipe/miRseq/arf_parse_mappings.pl $i -b 26 > $i.piRNA.26 ;done 
```
``` Label=4.norm  qsub=yes  workpath=%(outdir)s/result/4.norm
ln -s ../2.preprocess/*filter.fa .
if [ "%(Species)s" = "None" ];then
 '/home/rongzhengqin/pipe/miRseq/quantifier  --indir=../3.mapping --genome=../../database/$(basename %(Genome)s) --thread=8 --precursor=../../database/all.hairpin.fa --mature=../../database/all.mature.fa --specie=%(Species)s %(SampleInfo)s' + " %s"%('--plant' if self.config.get('Class')=='plant' else '')
else
 '/home/rongzhengqin/pipe/miRseq/quantifier  --indir=../3.mapping --genome=../../database/$(basename %(Genome)s) --thread=8 --precursor=../../database/%(Species)s_hairpin.fa --mature=../../database/%(Species)s_mature.fa --specie=%(Species)s --other-mature=../../database/no_%(Species)s_mature.fa %(SampleInfo)s' +" %s"%('--plant' if self.config.get('Class')=='plant' else '')
fi
mkdir Exprs/miRpredict;cd Exprs/miRpredict
python /home/rongzhengqin/pipe/miRseq/scan_predict.py quantifier_miRseq.novel.precursor.fa %(Class)s 1
sh Scan_microRNAs.sh
cat ./*/*.out > predict_result.xls
cd ..
sh /home/rongzhengqin/pipe/miRseq/screen_novel_miRpara.sh 
python /home/rongzhengqin/pipe/miRseq/plot_MEFI.py quantifier_miRseq.known_all_detected.stat.xls quantifier_miRseq.known_partial_detected.stat.xls quantifier_miRseq.novel.stat.xls 
ls *.stat.xls | while read i; do python /home/rongzhengqin/pipe/miRseq/miRdetect2html.py $i pdfs;done
mkdir pdfs;mv pdfs_* pdfs
python /home/rongzhengqin/pipe/miRseq/filter4nr_quant.py known_novel.exprs.matrix.anno > nr_known_novel.exprs.matrix.anno.xls
head=$(echo -e "#pre-miRNA\tmature\t"$(grep -v '^#' ../../0.info/sampleinfo.xls  |cut -f1 |perl -pwe 's/\\n/\\t/') )
ls quantifier_miRseq.*matrix.anno |xargs -I{} mv {} {}.xls
sed -i.bak "1i $head" nr_known_novel.exprs.matrix.anno.xls quantifier_miRseq.*matrix.anno.xls


```
``` Label=5.snqc qsub=yes  workpath=%(outdir)s/result/5.snqc require_job=4.norm
python /data/BIN/zhangsch/project/RNA/lib/exprs_qc.py ../0.info/sampleinfo.xls ../4.norm/Exprs/nr_known_novel.exprs.matrix.anno.xls 1
python /home/rongzhengqin/bin/stat_exprs_insamples.py ../0.info/sampleinfo.xls ../4.norm/Exprs/nr_known_novel.exprs.matrix.anno.xls  $(grep -v '#' ../0.info/sampleinfo.xls |wc -l)  ## 12 为样本数目(使用实际的样本数目)
```

``` Label=6.diff qsub=yes  workpath=%(outdir)s/result/6.diff require_job=4.norm
awk -F"\\t" '{print $1"|"$2"\\t"$0}' ../4.norm/Exprs/nr_known_novel.exprs.matrix.anno.xls |  cut -f 1,4-100 > readcounts.xls
head=$(grep -v '^#' ../0.info/sampleinfo.xls  |cut -f1 |perl -pwe 's/\\n/\\t/');sed -i "1i $head" readcounts.xls
grep -v "#" ../0.info/sampleinfo.xls | awk  '{print $5"\\t"$1}'  > samples.list
/data/tools/trinityrnaseq-2.2.0/Analysis/DifferentialExpression/run_DE_analysis.pl --matrix readcounts.xls --method edgeR --samples_file samples.list  --contrasts %(ContrastFile)s --output edgeR.diff.dir --dispersion 0.16
ls edgeR.diff.dir/readcounts.xls.*.edgeR.DE_results | while read i; do python /data/BIN/zhangsch/project/RNA/lib/s2_fmt_DEresult.py ${i} 1; done ## to check logFC\A3\A8A/B\A3\A9\A3\AC\C8\F4\D0\E8ҪlogFC(B/A)\A3\AC\D4\F2-1
 
 #awk -F"\\t" '{print $1"_vs_"$2}'  %(ContrastFile)s | while read i; do awk '$4<0.05' edgeR.diff.dir/readcounts.xls.${i}.edgeR.DE_results.Diff.total.xls >edgeR.diff.dir/readcounts.xls.${i}.edgeR.DE_results.Diff.sig.xls;done

awk -F"\\t" '{print $1"_vs_"$2}'  %(ContrastFile)s  | while read i; do mkdir $i ;done
awk -F"\\t" '{print $1"_vs_"$2}'  %(ContrastFile)s  | while read i; do cp edgeR.diff.dir/readcounts.xls.${i}.edgeR.DE_results.Diff.sig.xls ${i}/Diff.sig.xls ;done
awk -F"\\t" '{print $1"_vs_"$2}'  %(ContrastFile)s  | while read i; do cp edgeR.diff.dir/readcounts.xls.${i}.edgeR.DE_results.Diff.total.xls ${i}/Diff.total.xls ;done
awk -F"\\t" '{print $1"_vs_"$2}'  %(ContrastFile)s  | while read i; do cp edgeR.diff.dir/readcounts.xls.${i}.edgeR.DE_results.MA_n_Volcano.pdf ${i}/MA_n_Volcano.pdf ;done

  #cat  */Diff.sig.xls | grep -v "^#" |  cut -f 2 | sort |  uniq | python /home/rongzhengqin/scripts/select_fa.py - ../ > diffexprs.transcripts_coding.fa
```
``` Label=7.target qsub=yes  workpath=%(outdir)s/result/7.target require_job=6.diff
if [ %(Class)s = plant ] ;then
 cat ../4.norm/Exprs/quantifier_miRseq.known_all_detected.stat.xls ../4.norm/Exprs/quantifier_miRseq.known_partial_detected.stat.xls | grep -v "#" | cut -f 1,2 | sort | uniq | awk '{print ">"$1"\n"$2}' > detected.miRNA.fa
 cat ../4.norm/Exprs/quantifier_miRseq.novel.mature.fa >> detected.miRNA.fa
 sh /home/rongzhengqin/bin/microRNA_prediction/prog/kyj_test/run_target_predict.sh detected.miRNA.fa ../../database/%(Species)s.mrna.fa.gz ./ 2  &
else
 cat  ../6.diff/*/Diff.sig.xls >sig.all.xls
 python /home/rongzhengqin/bin/microRNA_prediction/seqfile.py sig.all.xls /data/database/miRbase/release-21/mature.fa ../4.norm/Exprs/screen.quantifier_miRseq.novel.mature.fa 
 /home/rongzhengqin/bin/microRNA_prediction/miRNA_target_predict --support=2 --prog=both --target=../../database/%(Species)s.utr3.fa.gz --outprefix=microRNApredict --html  sig.all.xls.seqdata None #--dbtar=/data/database/miRtarget_custom/microRNA_target.db.xls
fi
```

``` Label=8.target_func qsub=yes  workpath=%(outdir)s/result/8.target_func require_job=7.target,0.prepare.anno.pep
if [ %(Class)s = plant ] ;then
 TARGETFILE=../../7.target/miRNA_target_predict.txt
 UTR=../../../database/%(Species)s.mrna.fa.gz
else
 TARGETFILE=../../7.target/microRNApredict_all_predict.xls
 UTR=../../../database/%(Species)s.utr3.fa.gz
fi
if [ %(BlastKO_Result)s = None ]; then
 mkdir anno
 cat ../../database/temp_anno/leaf.*tsv >anno/known.novel.pep.fa.tsv
 cat ../../database/temp_anno/blast.ko.leaf*xls >anno/blast.ko.xls
 python /home/zhush/scripts/getKO.py /data/database/KEGG/Current/KO.id.list anno/blast.ko.xls /data/database/KEGG/Current/ko_pathway_name_class.list /data/database/KEGG/Current/ko_db.info 
 python /home/rongzhengqin/bin/AnnoGoKegg/ipr_go_fmt_v2.py anno/known.novel.pep.fa.tsv /data/database/GO/Current/obo_topology.txt /data/database/GO/Current/GO_alt_id.alt_id > known.novel.pep.fa.tsv.topo.xls
 BlastKO_Result=%(outdir)s/result/8.target_func/blast.ko.xls.KO.xls
 IPr_Result=%(outdir)s/result/8.target_func/known.novel.pep.fa.tsv.topo.xls
else
 BlastKO_Result=%(BlastKO_Result)s
 IPr_Result=%(IPr_Result)s
fi
awk -F"\\t" '{print $1"_vs_"$2}'  %(ContrastFile)s |while read i ;do 
  mkdir $i; cd $i; python /home/rongzhengqin/pipe/miRseq/miRNA_target_kegggo_fmt.py ../../6.diff/$i/Diff.sig.xls $TARGETFILE $UTR ttest >sig.xls;
  python /data/BIN/zhangsch/project/RNA/lib/miRNA/GO_Kegg.py  sig.xls backup_total.xls $IPr_Result $BlastKO_Result %(SampleInfo)s ../../4.norm/Exprs/nr_known_novel.exprs.matrix.anno.xls;cd ..;
  done
```

``` Label=report qsub=yes workpath=%(outdir)s/report/ require_job=All
ls %(outdir)s/result | grep -P '^[0-9]+' | while read i; do cp -R %(outdir)s/result/$i ./ ; done 
cp ../result/*.html ./

 #然后 拷贝配置文件：
cp -R /data/BIN/zhangsch/project/RNA/DATA/HELP /data/project/NCRNA/dist/ ./
cut -f1 0.info/sampleinfo.xls |grep -v "^#" | xargs -i rm -r 2.preprocess/{}
mv 4.norm/{Exprs,pdfs} . && rm -r 4.norm/* && mv Exprs/* pdfs 4.norm/
rm 2.preprocess/Rfam_anno/ 3.mapping/*fa  4.norm/*{anno,log,miRpredict} 6.diff/{edgeR.diff.dir,readcounts.xls} 7.target/{sig.all.xls,.tmp.}* 7.target/*{miRanda,targetscan}* Exprs/ -r
rm 8.target_func/* */run*sh{'',.o,.e}* */*log
 #python /data/BIN/zhangsch/project/RNA/scripts/genome_guild_ncRNA_v5.py %(SampleInfo)s %(ContrastFile)s 
python /data/BIN/zhangsch/project/RNA/lib/miRNA/miRNA_report.v1.py %(SampleInfo)s %(ContrastFile)s %(config)s
 #py /home/lizhenzhong/bin/ftp_client/ftp_client.py -I HN16025000.report.tar.gz --project HN16025000 --manager xuzhenhua
```
