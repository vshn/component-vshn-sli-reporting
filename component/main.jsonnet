// main template for vshn-sli-reporting
local common = import 'common.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local netPol = import 'networkpolicies.libsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.vshn_sli_reporting;


local formatImage = function(ref) '%(registry)s/%(repository)s:%(tag)s' % ref;

local lieutenantSecret = kube.Secret('lieutenant-credentials') {
  metadata+: {
    namespace: params.namespace,
    labels+: common.Labels,
  },
  stringData: {
    [name]: params.sli_reporting.lieutenant[name]
    for name in std.objectFields(params.sli_reporting.lieutenant)
  },
};

local authSecret = kube.Secret('vshn-sli-reporting-auth') {
  metadata+: {
    namespace: params.namespace,
    labels+: common.Labels,
  },
  stringData: {
    [name]: params.sli_reporting.auth[name]
    for name in std.objectFields(params.sli_reporting.auth)
  },
};

local env = [
  {
    name: 'VSR_AUTH_USER',
    value: params.sli_reporting.auth.user,
  },
  {
    name: 'VSR_AUTH_PASS',
    valueFrom: {
      secretKeyRef: {
        name: authSecret.metadata.name,
        key: 'password',
      },
    },
  },
  {
    name: 'VSR_LIEUTENANT_NAMESPACE',
    value: params.sli_reporting.lieutenant.namespace,
  },
  {
    name: 'VSR_LIEUTENANT_SA_TOKEN',
    valueFrom: {
      secretKeyRef: {
        name: lieutenantSecret.metadata.name,
        key: 'sa_token',
      },
    },
  },
  {
    name: 'VSR_LIEUTENANT_K8S_URL',
    valueFrom: {
      secretKeyRef: {
        name: lieutenantSecret.metadata.name,
        key: 'k8s_url',
      },
    },
  },
];

local container = {
  image: formatImage(params.images.sli_reporting),
  command: [ 'vshn-sli-reporting' ],
  args: [ 'serve' ],
  ports: [
    {
      containerPort: 8080,
    },
  ],
  volumeMounts: [ {
                  name: 'vshn-sli-reporting-db',
                  mountPath: '/data',
                } ]
                + [
                  { name: name } + params.sli_reporting.extra_volumes.vshn_sli_reporting[name].mount_spec
                  for name in std.objectFields(params.sli_reporting.extra_volumes.vshn_sli_reporting)
                ],
  env: env,
};

local sts = kube.StatefulSet('vshn-sli-reporting') {
  metadata+: {
    namespace: params.namespace,
    labels+: common.Labels,
  },
  spec+: {
    resources: {
      requests: {
        memory: params.sli_reporting.resources.requests.memory,
        cpu: params.sli_reporting.resources.requests.cpu,
      },
      limits: {
        [if std.objectHas(params.sli_reporting.resources.limits, 'memory') then 'memory']: std.get(params.sli_reporting.resources.limits, 'memory'),
        [if std.objectHas(params.sli_reporting.resources.limits, 'cpu') then 'cpu']: std.get(params.sli_reporting.resources.limits, 'cpu'),
      },
    },
    template+: {
      metadata+: {
        labels+: common.Labels,
      },
      spec+: {
        initContainers: [
          container {
            name: 'db-init',
            args: [
              'db',
              'init',
              '--db-file',
              params.sli_reporting.db_file,
            ],
          },
        ],
        containers: [
          container {
            name: 'vshn-sli-reporting',
            args: [
              'serve',
              '--auth-user',
              '$(VSR_AUTH_USER)',
              '--auth-pass',
              '$(VSR_AUTH_PASS)',
              '--lieutenant-namespace',
              '$(VSR_LIEUTENANT_NAMESPACE)',
              '--lieutenant-k8s-url',
              '$(VSR_LIEUTENANT_K8S_URL)',
              '--lieutenant-sa-token',
              '$(VSR_LIEUTENANT_SA_TOKEN)',
              '--db-file',
              params.sli_reporting.db_file,
              'port',
              '8080',
              '--host',
              '0.0.0.0',
            ],
          },
        ],
        [if std.length(params.sli_reporting.extra_volumes.vshn_sli_reporting) > 0 then 'volumes']: [
          { name: name } + params.sli_reporting.extra_volumes.vshn_sli_reporting[name].volume_spec
          for name in std.objectFields(params.sli_reporting.extra_volumes.vshn_sli_reporting)
        ],
      },
    },
    volumeClaimTemplates+: [

      {
        metadata+: {
          labels+: common.Labels,
          name: 'vshn-sli-reporting-db',
        },
        spec: {
          accessModes: [ 'ReadWriteOnce' ],
          resources: {
            requests: {
              storage: params.sli_reporting.resources.requests.storage,
            },
          },
        },
      },
    ],
  },
};

{
  '00_namespace': kube.Namespace(params.namespace) {
    metadata+: {
      labels+: common.Labels,
    } + com.makeMergeable(params.namespaceMetadata),
  },
  '01_netpols': netPol.Policies,
  '10_auth_secret': authSecret,
  '10_lieutenant_secret': lieutenantSecret,
  '30_sts': sts,
}
