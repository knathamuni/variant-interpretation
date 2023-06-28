version 1.0

import "Structs.wdl"

workflow IGV_Evidence {
    input{
        File varfile
        String family
        File ped_file
        Array[String] samples
        File reference
        File reference_index
        String buffer
        String buffer_large
        String igv_docker
        Array[File] split_reads
        Array [File] disc_reads
        Array [File] read_depth
        RuntimeAttr? runtime_attr_igv
    }

    call runIGV_whole_genome_localize{
        input:
            varfile = varfile,
            family = family,
            ped_file = ped_file,
            samples = samples,
            reference = reference,
            reference_index = reference_index,
            buffer = buffer,
            buffer_large = buffer_large,
            igv_docker = igv_docker,
            split_reads = split_reads,
            disc_reads = disc_reads,
            read_depth = read_depth,
            runtime_attr_override = runtime_attr_igv
    }

    output{
        File tar_gz_pe = runIGV_whole_genome_localize.pe_plots
    }
}

task reformat_split{
    input{
        File split_reads
        String igv_docker
        RuntimeAttr? runtime_attr_override
        }

    Float input_size = size(select_all([split_reads]), "GB")
    Float base_mem_gb = 3.75

    RuntimeAttr default_attr = object {
                                      mem_gb: base_mem_gb,
                                      disk_gb: ceil(10 + input_size),
                                      cpu: 1,
                                      preemptible: 2,
                                      max_retries: 1,
                                      boot_disk_gb: 8
                                  }

    RuntimeAttr runtime_attr = select_first([runtime_attr_override, default_attr])

    String output_split_reads = split_reads

    command <<<
        set -euo pipefail

        zcat ~{split_reads} | \
            awk -F"\t" 'BEGIN { OFS="\t" }{print $1,$2-5,$2+5,$3,$4}' | \
            sed -e 's/left/-/g' | sed -e 's/right/+/g' | bgzip -c > ~{output_split_reads}
    >>>

    runtime {
        cpu: select_first([runtime_attr.cpu, default_attr.cpu])
        memory: "~{select_first([runtime_attr.mem_gb, default_attr.mem_gb])} GB"
        disks: "local-disk ~{select_first([runtime_attr.disk_gb, default_attr.disk_gb])} HDD"
        bootDiskSizeGb: select_first([runtime_attr.boot_disk_gb, default_attr.boot_disk_gb])
        preemptible: select_first([runtime_attr.preemptible, default_attr.preemptible])
        maxRetries: select_first([runtime_attr.max_retries, default_attr.max_retries])
        docker: igv_docker
    }
    output{
        File pe_plots="~{family}_pe_igv_plots.tar.gz"
        Array[File] pe_txt = glob("pe.*.txt")
        Array[File] pe_sh = glob("pe.*.sh")
        Array[File] varfile = glob("new.varfile.*.bed")
        }
    }


task runIGV_whole_genome_localize{
        input{
            File varfile
            File reference
            File reference_index
            String family
            File ped_file
            Array[String] samples
            Array[File] crams
            Array[File] crais
            String buffer
            String buffer_large
            String igv_docker
            RuntimeAttr? runtime_attr_override
        }

    Float input_size = size(select_all([varfile, ped_file]), "GB")
    Float base_mem_gb = 3.75

    RuntimeAttr default_attr = object {
                                      mem_gb: base_mem_gb,
                                      disk_gb: ceil(10 + input_size),
                                      cpu: 1,
                                      preemptible: 2,
                                      max_retries: 1,
                                      boot_disk_gb: 8
                                  }

    RuntimeAttr runtime_attr = select_first([runtime_attr_override, default_attr])

    command <<<
            set -euo pipefail
            mkdir pe_igv_plots
            i=0
            while read -r line
            do
                let "i=$i+1"
                echo "$line" > new.varfile.$i.bed
                python /src/makeigvpesr.py -v new.varfile.$i.bed -fam_id ~{family} -samples ~{sep="," samples} -crams ${write_lines(crams)} -p ~{ped_file} -o pe_igv_plots -b ~{buffer} -l ~{buffer_large} -i pe.$i.txt -bam pe.$i.sh
                bash pe.$i.sh
                xvfb-run --server-args="-screen 0, 1920x540x24" bash /IGV_Linux_2.16.0/igv.sh -b pe.$i.txt
            done < ~{varfile}
            tar -czf ~{family}_pe_igv_plots.tar.gz pe_igv_plots

        >>>

    runtime {
        cpu: select_first([runtime_attr.cpu, default_attr.cpu])
        memory: "~{select_first([runtime_attr.mem_gb, default_attr.mem_gb])} GB"
        disks: "local-disk ~{select_first([runtime_attr.disk_gb, default_attr.disk_gb])} HDD"
        bootDiskSizeGb: select_first([runtime_attr.boot_disk_gb, default_attr.boot_disk_gb])
        preemptible: select_first([runtime_attr.preemptible, default_attr.preemptible])
        maxRetries: select_first([runtime_attr.max_retries, default_attr.max_retries])
        docker: igv_docker
    }
    output{
        File pe_plots="~{family}_pe_igv_plots.tar.gz"
        Array[File] pe_txt = glob("pe.*.txt")
        Array[File] pe_sh = glob("pe.*.sh")
        Array[File] varfile = glob("new.varfile.*.bed")
        }
    }