/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { FASTQC                 } from '../modules/nf-core/fastqc/main'
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { SIMPLEAF_INDEX         } from '../modules/nf-core/simpleaf/index/main'
include { SIMPLEAF_QUANT         } from '../modules/nf-core/simpleaf/quant/main'
include { ALEVINQC               } from '../modules/local/alevinqc'
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_miniranger_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow MINIRANGER {

    take:
    ch_samplesheet // channel: samplesheet read in from --input
    ch_genome_fasta
    ch_genome_gtf

    main:

    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    chemistry_config = Utils.getChemistry(workflow, log, params.chemistry)
    bc_whitelist = file("$projectDir/${chemistry_config['whitelist']}", checkIfExists: true)


    //
    // MODULE: Run FastQC
    //
    FASTQC (
        ch_samplesheet
    )
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.collect{it[1]})
    ch_versions = ch_versions.mix(FASTQC.out.versions.first())

    //
    // MODULE: SimpleAF Index
    //
    ch_genome_fasta_gtf = ch_genome_fasta.combine( ch_genome_gtf ).map{ fasta, gtf -> [[id: "ref"], fasta, gtf] }
    //ch_genome_fasta_gtf.view()

    SIMPLEAF_INDEX (
        ch_genome_fasta_gtf,
        [[:], []], // meta, transcript FASTA
        [[:], []], // meta, probe CSV
        [[:], []] // meta, feature CSV
    )
    // Channel of tuple(meta, index dir)
    simpleaf_ref    = SIMPLEAF_INDEX.out.ref

    // Channel of version
    ch_versions = ch_versions.mix( SIMPLEAF_INDEX.out.versions )

    //
    // MODULE: SimpleAF Quant
    //

    // meta, chemistry, reads
    ch_quant_reads = ch_samplesheet.map{ meta, reads -> 
        [meta + ["chemistry": params.chemistry], params.chemistry, reads] 
    }
    // meta, index, t2g mapping
    txp2gene = SIMPLEAF_INDEX.out.t2g.map{ meta, t2g_file -> t2g_file }
    ch_quant_index = SIMPLEAF_INDEX.out.index.combine(txp2gene).collect()

    ch_quant_reads.view()
   
    SIMPLEAF_QUANT (
        ch_quant_reads,
        ch_quant_index,
        [[:], "unfiltered-pl", [], bc_whitelist ], // meta, cell filtering strategy
        params.umi_resolution, 
        [[:], []] // meta, mapping results
    )
    ch_versions = ch_versions.mix(SIMPLEAF_QUANT.out.versions)
    ch_af_map = SIMPLEAF_QUANT.out.map
    ch_af_quant = SIMPLEAF_QUANT.out.quant

    //
    // MODULE: AlevinQC
    //
    ALEVINQC (
        ch_af_quant,
        ch_af_quant,
        ch_af_map,
    )
    ch_versions = ch_versions.mix(ALEVINQC.out.versions)

    
    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name:  'miniranger_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }


    //
    // MODULE: MultiQC
    //
    ch_multiqc_config        = Channel.fromPath(
        "$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config = params.multiqc_config ?
        Channel.fromPath(params.multiqc_config, checkIfExists: true) :
        Channel.empty()
    ch_multiqc_logo          = params.multiqc_logo ?
        Channel.fromPath(params.multiqc_logo, checkIfExists: true) :
        Channel.empty()

    summary_params      = paramsSummaryMap(
        workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary = Channel.value(paramsSummaryMultiqc(summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_custom_methods_description = params.multiqc_methods_description ?
        file(params.multiqc_methods_description, checkIfExists: true) :
        file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = Channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description))

    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true
        )
    )

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        []
    )

    emit:multiqc_report = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
