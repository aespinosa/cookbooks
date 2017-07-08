import jenkins.model.Jenkins;
import hudson.model.FreeStyleProject;

if (! Jenkins.instance.getItem('seed') ) {
  job = Jenkins.instance.createProject(FreeStyleProject, 'seed')
  job.displayName = 'Seed Job'

  builder = new javaposse.jobdsl.plugin.ExecuteDslScripts()
  builder.usingScriptText = false
  builder.targets = 'seed.groovy'
  builder.removedJobAction = javaposse.jobdsl.plugin.RemovedJobAction.DELETE
  builder.removedViewAction = javaposse.jobdsl.plugin.RemovedViewAction.DELETE
  builder.lookupStrategy = javaposse.jobdsl.plugin.LookupStrategy.JENKINS_ROOT

  job.buildersList.add(builder)

  job.save()

  job.scheduleBuild2(10)
}

