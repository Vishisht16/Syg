# Network policy

A NetworkPolicy is easy to write and hard to get right. It selects pods by
label, its peers are label selectors, the API server fills in `policyTypes` if
you leave it out (in a way that isolates ingress you never mentioned), and a
policy that cuts a path your service depends on applies cleanly and fails at
the first request. Syg writes policies from names, derives the paths your
services need, and checks the two against each other.

## Declaring a policy

```syg
module shop

service api {
  image "registry.example.com/api:1.4.2"
  replicas 2
  port http 8080
  resources { cpu 100m, memory 128Mi }
  health { ready GET :http /readyz }
  internal :http
  policy api-net
}

policy api-net {
  ingress { web :http }
}

service web {
  image "registry.example.com/web:3.0.1"
  replicas 2
  port http 8080
  resources { cpu 100m, memory 128Mi }
  health { ready GET :http /readyz }
  needs service api :http
  policy web-net
}

policy web-net {
  egress {}
}
```

- A **policy** lists peers for `ingress`, `egress`, or both. A block that is
  present isolates that direction; a block that is absent leaves it open. An
  empty block, `egress {}`, admits nothing beyond what Syg derives.
- A **peer** is a workload of the module, an `extern service` (in another
  namespace, with `namespace "..."`), an `extern host` (an address outside the
  cluster), or `apiserver` (egress only). Never a selector: Syg writes the
  selector from the name.
- A workload uses a policy with `policy NAME`. Each workload that uses one gets
  its own NetworkPolicy, whose `podSelector` is the workload's derived
  selector and whose `policyTypes` is always written out.
- `needs service NAME :PORT` declares a dependency. It does two things: the
  depending workload's egress allows it, and Syg checks the other end admits
  it.

## What Syg adds for you

The rules Syg derives, so you do not write them and cannot forget them:

- **DNS**: an isolated egress allows UDP and TCP 53, or nothing resolves.
- **Exposed ports**: a port you `expose` is reachable from anywhere, or the
  route would serve nothing.
- **Dependencies**: each `needs service` is allowed out of the depending
  workload.
- **The API server**, for an identity with grants, when you list `apiserver`:
  both 443 and 6443, because a policy sees the translated port.

Each derived rule is recorded in the provenance, with its reason.

## What Syg checks

If `api-net` were `ingress {}`, web's dependency would be cut:

```console
error[policy-blocks-dependency]: web needs api :http, and api does not admit web
  --> shop.syg:23:3
     |
  23 |   needs service api :http
     |   ^^^^^^^^^^^^^^^^^^^^^^^
  --> shop.syg:14:3
     |
  14 |   ingress {}
     |   ^^^^^^^^^^ policy api-net isolates api and allows nothing on this path
   = consequence: the connection is refused or times out, as the network plugin chooses, and neither object's status says why
   = help: add `web :http` to policy api-net's ingress
```

CHK-NP-002 judges every required path (each dependency, DNS, each exposed
port, the API server for an identity with grants) against every policy that
selects either end. That includes raw NetworkPolicies in the module, with the
API server's defaulted `policyTypes` modelled. A raw peer Syg cannot evaluate,
such as a namespace label or an address block, gives a coverage note rather
than a guess.

CHK-NP-003 is a note per isolated workload, saying what it can reach and what
reaches it. `syg graph -reachability` prints the whole matrix:

```console
$ syg graph -reachability shop
from \ to  api:http  web:http
api        no        yes
web        yes       no
```

## Whether the cluster enforces it

NetworkPolicy is an API object. Enforcement is the network plugin's, and some
plugins (flannel, for one) enforce none: every policy is accepted, and nothing
is blocked. Syg cannot know that from source, so every policy note says
enforcement is unverified, and with a [snapshot](checks.md#snapshots), CHK-T2-NET-002
warns when the cluster's plugin does not enforce policy.

Syg never writes a namespace-wide default-deny. That is a platform decision, and
one Syg's checks take into account when it appears as a raw policy.
