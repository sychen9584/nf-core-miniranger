import groovy.json.JsonSlurper

class WorkflowMiniranger {
    // Retrieve the aligner-specific protocol based on the specified protocol.
    // Returns a map ["protocol": protocol, "extra_args": <extra args>, "whitelist": <path to whitelist>]
    // extra_args and whitelist are optional.
    public static Map getChemistry(workflow, log, chemistry) {
        def jsonSlurper = new JsonSlurper()
        def json = new File("${workflow.projectDir}/assets/chemistries.json").text
        def chemistries = jsonSlurper.parseText(json)
        if(chemistries.containsKey(chemistry)) {
            return chemistries[chemistry]
        } else {
            log.warn("Chemistry '${chemistry}' not recognized by the pipeline. Passing on the chemistry to the aligner unmodified.")
            return ["chemistry": chemistry]
        }
    }

}