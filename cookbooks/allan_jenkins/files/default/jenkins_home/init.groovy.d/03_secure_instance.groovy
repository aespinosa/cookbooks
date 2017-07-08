cli = jenkins.CLI.get()
cli.enabled = false
cli.save()

import jenkins.model.Jenkins;
Jenkins.instance.injector.getInstance(jenkins.security.s2m.AdminWhitelistRule.class).setMasterKillSwitch(false)

dsl = Jenkins.instance.injector.getInstance(javaposse.jobdsl.plugin.GlobalJobDslSecurityConfiguration.class)
dsl.useScriptSecurity = false
dsl.save()

import org.jenkinsci.plugins.GithubSecurityRealm;
import hudson.security.HudsonPrivateSecurityRealm;

// Jenkins.instance.securityRealm = new GithubSecurityRealm(
//    'https://github.com', 'https://api.github.com', 'x', 'y')
Jenkins.instance.securityRealm = new HudsonPrivateSecurityRealm(false, false, null);

permissions = new hudson.security.GlobalMatrixAuthorizationStrategy()

permissions.add(Jenkins.ADMINISTER, 'aespinosa')
permissions.add(hudson.model.View.READ, 'anonymous')
permissions.add(hudson.model.Item.READ, 'anonymous')
permissions.add(Jenkins.READ, 'anonymous')

Jenkins.instance.authorizationStrategy = permissions
Jenkins.instance.save()

