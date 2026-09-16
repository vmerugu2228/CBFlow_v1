# Cloud EDA

## Overview

Cloud computing is reshaping how semiconductor companies run EDA workloads. Traditionally, chip design required massive on-premises compute farms with thousands of servers, petabytes of storage, and complex license management. Cloud EDA enables flexible, scalable compute resources that can be provisioned on demand, reducing capital expenditure and eliminating the constraint of fixed on-premises capacity. This guide covers the practical aspects of cloud EDA from a PD engineer's perspective: hybrid architectures, burst compute, security, licensing, data transfer, and the emerging commercial offerings.

## Why Cloud EDA?

### The Compute Challenge

Modern physical design workloads are enormous:

- A single PnR run on a large block can require 256-512GB of RAM and 8-32 CPU cores for 12-48 hours
- Signoff STA across 50+ MMMC scenarios requires hundreds of parallel licenses
- Full-chip DRC on a large SoC can take 24-72 hours on a powerful machine
- Design space exploration (running 100+ parameter combinations) multiplies the compute by 100x

On-premises infrastructure must be sized for peak demand (tapeout crunch), which means it is underutilized 80% of the time. Cloud computing eliminates this waste by providing compute on demand.

### Economic Drivers

- **CapEx to OpEx**: Replace large upfront hardware purchases with pay-per-use compute
- **Elasticity**: Scale from 100 cores to 10,000 cores in minutes during tapeout crunch
- **Latest hardware**: Access to the newest CPU/GPU/memory configurations without hardware refresh cycles
- **Geographic distribution**: Teams in multiple locations can access the same compute environment

### Business Realities

- **Not free**: Cloud compute costs can exceed on-premises costs for sustained workloads
- **Not simple**: Security, data transfer, license management, and workflow integration require careful planning
- **Not optional**: Competitive pressure is forcing the industry toward cloud adoption

## Hybrid Cloud Architecture

### Concept

Most semiconductor companies adopt a hybrid model: on-premises infrastructure for steady-state workloads, with cloud burst for peak demand.

```
On-Premises (steady state):
- Day-to-day PnR runs
- Interactive design work (GUI sessions)
- Data storage and management
- License servers

Cloud (burst):
- Tapeout crunch (dozens of parallel runs)
- Design space exploration (100+ parameter sweeps)
- Full-chip signoff (DRC/LVS/STA across all corners)
- Regression testing
```

### Architecture Components

**Job scheduler**: A workload manager (LSF, Slurm, PBS) that can dispatch jobs to both on-premises and cloud machines. The scheduler must be cloud-aware, able to provision cloud instances on demand.

**Storage layer**: A shared filesystem accessible from both on-premises and cloud. Options include:
- NFS over VPN (simple but slow for large data)
- Cloud-native storage (S3, EFS, FSx) with data synchronization
- Hybrid storage appliances (NetApp, Pure Storage with cloud tiering)

**Network connection**: High-bandwidth, low-latency connection between on-premises and cloud:
- AWS Direct Connect, Azure ExpressRoute, or GCP Dedicated Interconnect
- Typical bandwidth: 1-10 Gbps dedicated link
- VPN as a backup or for lower-bandwidth needs

**Identity and access management**: Unified authentication across on-premises and cloud (LDAP, Active Directory integration with cloud IAM).

## Burst Compute

### When to Burst

Burst to the cloud when:

- On-premises queue wait times exceed acceptable thresholds
- A deadline requires running more parallel jobs than on-premises capacity allows
- A one-time compute-intensive task (design space exploration, regression) would monopolize on-premises resources
- New hardware configurations (high-memory instances, latest CPUs) are needed for a specific workload

### Burst Workflow

1. **Job submission**: Engineer submits a job to the scheduler
2. **Queue evaluation**: Scheduler detects that on-premises resources are insufficient
3. **Instance provisioning**: Scheduler requests cloud instances (via API or auto-scaling group)
4. **Data staging**: Required design data is transferred to the cloud instance (or is already on cloud storage)
5. **Job execution**: EDA tool runs on the cloud instance with the cloud-hosted license
6. **Result collection**: Output data is transferred back to on-premises storage
7. **Instance termination**: Cloud instance is terminated to stop billing

### Optimization Strategies

- **Spot instances**: Use cloud spot/preemptible instances for non-critical, restartable workloads at 60-80% cost savings. Not suitable for long-running PnR jobs that cannot be checkpointed
- **Right-sizing**: Match instance type to workload (memory-optimized for STA, compute-optimized for DRC, general-purpose for PnR)
- **Instance reuse**: Keep instances warm between jobs in a burst window to avoid startup latency
- **Data locality**: Stage data to cloud storage before the burst; minimize real-time data transfer

## Security Considerations

### The Stakes

Semiconductor design data is among the most sensitive IP in any industry. A chip design represents billions of dollars in R&D investment. A leak could enable competitors to clone the design or identify vulnerabilities.

### Security Requirements

**Data encryption**:
- Encrypt data in transit (TLS 1.3 for all connections)
- Encrypt data at rest (AES-256 for storage volumes)
- Encrypt EDA license traffic

**Network isolation**:
- Dedicated VPC (Virtual Private Cloud) with no public internet access
- VPN or dedicated network link to on-premises (no public internet routing)
- Security groups/firewalls restricting intra-VPC traffic to required ports only

**Access control**:
- Role-based access control (RBAC) for cloud resources
- Multi-factor authentication (MFA) for all human access
- Service accounts with minimal required permissions for automated workflows

**Data residency**:
- Design data may be restricted to specific geographic regions (e.g., US-only for ITAR-controlled designs)
- Cloud provider must guarantee data does not leave the specified region

**Audit and compliance**:
- Full audit logging of all data access and job execution
- Compliance with industry standards (ISO 27001, SOC 2, NIST 800-171)
- Regular security assessments and penetration testing

### Foundry and Customer Requirements

Foundries (TSMC, Samsung, Intel) have specific security requirements for handling their PDK data in the cloud. These may include:

- Approved cloud providers and regions
- Required encryption standards
- Audit requirements
- Data deletion procedures after project completion

Design teams must verify that their cloud setup meets all foundry and customer security requirements before moving any PDK data to the cloud.

## License Management

### The License Challenge

EDA tools are licensed, and licenses are expensive (a single PrimeTime license can cost tens of thousands of dollars per year). In the cloud:

- License servers must be accessible from cloud instances
- License usage must be tracked across on-premises and cloud
- Burst compute can create sudden demand spikes for licenses

### License Models

**On-premises license server**: Keep the license server on-premises and access it from cloud instances over the VPN. Simple but adds latency and depends on VPN reliability.

**Cloud-hosted license server**: Run the license server on a dedicated cloud instance. Lower latency for cloud jobs but requires managing the server in the cloud.

**Token-based licensing**: EDA vendors offer token-based licensing where a pool of tokens can be dynamically allocated to different tools. More flexible for cloud burst scenarios.

**Cloud-native licensing**: Some EDA vendors offer cloud-specific licensing models:
- Pay-per-use (billed by runtime rather than annual license)
- Cloud-bundled (compute + license in a single offering)
- Subscription with cloud burst allowance

### Vendor Offerings

- **Synopsys Cloud**: Synopsys-hosted cloud platform with pre-integrated tools, licensing, and compute. Available on AWS and Azure
- **Cadence CloudBurst**: Cloud burst solution integrated with Cadence tools
- **Siemens EDA Cloud**: Cloud-hosted Siemens EDA tools on various cloud providers

### License Optimization

- **License queuing**: Rather than provisioning more licenses, queue jobs and run them when licenses become available
- **License harvesting**: Automatically reclaim idle licenses from on-premises users during burst periods
- **Staggered scheduling**: Schedule cloud jobs to avoid simultaneous license peaks
- **Tool version consolidation**: Standardize on fewer tool versions to reduce license fragmentation

## Data Transfer

### The Bandwidth Problem

Design databases are large:

- A single block PnR database: 10-100 GB
- Full-chip GDSII: 50-500 GB
- Parasitic extraction files: 10-100 GB per corner
- STA databases: 5-50 GB per scenario

Transferring this data over the network takes time and costs money.

### Data Transfer Strategies

**Pre-staging**: Copy design data to cloud storage before the burst window. Schedule data transfers during off-peak hours.

**Incremental sync**: Use tools like rsync or cloud-native sync (AWS DataSync, Azure File Sync) to transfer only changed files.

**Data tiering**: Keep frequently accessed data on high-performance cloud storage (EBS, FSx); archive older data to cheaper storage (S3, Glacier).

**Compute near data**: If the design data is already in the cloud (e.g., synthesis was done in the cloud), keep subsequent PnR and signoff in the cloud too. Avoid round-tripping data.

**Compression**: Compress design files before transfer. GDSII and database files compress well (2-5x reduction).

### Cost Considerations

Cloud providers charge for data egress (data leaving the cloud). At $0.05-0.09/GB, transferring 1TB costs $50-90 per transfer. This adds up:

- 100 burst runs x 50GB per run = 5TB of data movement = $250-450 per burst cycle
- Plan data transfer costs into the cloud budget

## Workflow Integration

### Job Scheduler Integration

The most critical integration point. The scheduler must:

- Transparently dispatch jobs to on-premises or cloud based on resource availability and cost
- Provision and deprovision cloud instances automatically
- Handle job failures and retries on cloud instances
- Track resource usage for chargeback and cost reporting

**Tools**: IBM LSF with cloud connectors, Altair PBS Pro with cloud integration, SLURM with cloud plugins, custom solutions using Terraform/Ansible.

### EDA Tool Configuration

EDA tools running in the cloud must be configured with:

- Correct tool versions (matching on-premises for consistency)
- Environment variables and setup scripts
- Technology files, libraries, and PDK access
- License server connectivity

Use containerization (Docker) or machine images (AMIs) to create pre-configured environments that can be launched instantly.

### Results Management

After cloud jobs complete:

- Copy results back to on-premises storage (or centralized cloud storage)
- Parse reports and update the QoR tracking database
- Clean up temporary cloud storage and terminate instances
- Verify results match on-premises baseline (tool version consistency check)

## Cost Management

### Cost Components

| Component | Typical Cost |
|-----------|-------------|
| Compute (per core-hour) | $0.03-0.10 |
| Memory (per GB-hour) | $0.005-0.015 |
| Storage (per GB-month) | $0.02-0.10 |
| Data transfer (egress, per GB) | $0.05-0.09 |
| Network (dedicated link, monthly) | $500-5000 |
| Licenses (varies widely) | $100-1000/day per tool |

### Cost Optimization

1. **Right-size instances**: Do not use a 1TB RAM instance for a job that needs 128GB
2. **Spot instances**: Use for non-critical, restartable workloads (60-80% savings)
3. **Reserved capacity**: For predictable baseline workloads, reserve instances at 30-50% discount
4. **Auto-termination**: Ensure instances are terminated when jobs complete; orphaned instances waste money
5. **Budget alerts**: Set spending alerts to catch runaway costs early
6. **Chargeback**: Allocate costs to projects/teams to create accountability

## Future of Cloud EDA

The industry is moving toward cloud-native EDA workflows where the cloud is the primary compute environment, not just a burst resource. Enabling trends include:

- EDA vendors building cloud-native tools optimized for cloud infrastructure
- Improved security frameworks satisfying even the most stringent IP protection requirements
- Better integration between design tools and cloud-native services (ML training, data analytics)
- Multi-cloud strategies providing vendor independence and resilience
- Edge computing for latency-sensitive interactive workloads (GUI sessions)

PD engineers should be prepared for a future where cloud is the default compute environment, with on-premises reserved for interactive work and the most security-sensitive tasks.
