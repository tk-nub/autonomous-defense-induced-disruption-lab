# Experimental Design and Measurement Model

## 1. Purpose of This Document

This document formalizes the experimental structure used to evaluate Autonomous Defense Induced Disruption (ADID) within a hybrid enterprise lab environment.

The objective is to define:

- Research questions
- Hypothesis
- Experimental variables
- Trigger boundary logic
- Measurement methodology
- Propagation assessment
- Recovery impact analysis
- Study limitations

This document serves as the methodological foundation for evaluating autonomous containment behavior in detection-driven security systems.

---

## 2. Research Objective

To determine whether detection-driven autonomous containment mechanisms can produce enterprise-wide operational denial independent of attacker persistence or infrastructure compromise.

This study evaluates containment as a decision architecture rather than as a product feature.

---

## 3. Research Questions

1. Can high-confidence incident classification alone trigger enterprise-scale containment?
2. Is automated enforcement gated by incident classification rather than alert volume?
3. Does enforcement propagate across correlated identities and devices?
4. Are privileged or administrative accounts inherently protected from automated containment?
5. Can autonomous enforcement impair recovery capability by restricting control-plane access?

---

## 4. Hypothesis

Autonomous containment systems operating under Artificial Narrow Intelligence (ANI) will enforce protective actions based on detection-confidence thresholds without evaluating organizational context, resulting in operational disruption proportional to entity correlation rather than business criticality.

---

## 5. Experimental Variables

### 5.1 Independent Variables (Manipulated)

The following elements are intentionally generated or influenced during experimentation:

- Identity risk telemetry (external authentication activity)
- Endpoint compromise telemetry (Atomic Red Team techniques)
- Cross-domain signal correlation (identity + endpoint)
- User population composition
- Presence of privileged accounts
- Hybrid synchronization configuration

---

### 5.2 Dependent Variables (Observed)

The following system behaviors are measured:

- Incident classification type
- Incident severity level
- Automated containment actions executed
- Identity disablement events
- Endpoint containment events
- Propagation scope across correlated entities
- Administrative account status
- Recovery requirements

---

### 5.3 Controlled Variables

The following elements remain constant to preserve experimental consistency:

- Microsoft 365 E5 tenant configuration
- Defender XDR configuration
- Attack Disruption enabled state
- Hybrid identity topology
- Licensing model
- Enterprise network architecture

---

## 6. Observable Trigger Boundary

This research does not claim knowledge of proprietary internal detection confidence scores.

Instead, the observable enforcement boundary is defined as:

1. Incident classification within the "Attack Disruption" family
2. Incident severity elevated to High
3. Automated containment actions recorded in Defender Actions export

Containment is considered triggered when automated actions such as:

- DisableUser
- RequireUserToSignInAgain
- SuspendUser
- ContainUser or ContainDevice

are executed following incident classification.

The trigger boundary is therefore defined at the incident-classification level rather than alert volume or entity count.

---

## 7. Measurement Model

### 7.1 Evidence Sources

Evidence is collected from:

- Defender Alerts export
- Defender Incidents queue export
- Defender Automated Actions export
- Identity account state validation
- Endpoint containment state validation

---

### 7.2 ADID Confirmation Sequence

Autonomous Defense Induced Disruption is confirmed when the following sequence occurs:

1. Precursor telemetry signals recorded.
2. Incident classified within Attack Disruption family.
3. Severity elevated to High.
4. Automated containment actions executed.
5. Identity or endpoint access disabled.
6. Organizational authentication capability degraded.

The study focuses on correlating incident classification timestamps with containment execution timestamps to establish causal linkage.

---

## 8. Propagation Assessment

Propagation is evaluated by:

- Identifying all correlated entities affected by containment.
- Counting disabled accounts relative to initial signal origin.
- Evaluating hybrid synchronization impact.
- Assessing containment spread across identity and endpoint layers.

The study evaluates whether enforcement scope scales according to entity correlation rather than operational role or business dependency.

---

## 9. Recovery Impact Assessment

Recovery analysis evaluates:

- Whether non-privileged users regain access automatically.
- Whether privileged accounts remain operational.
- Whether manual intervention is required.
- Whether break-glass mechanisms are necessary.
- Whether external vendor support would be required absent exclusion controls.

Particular attention is given to scenarios in which privileged or domain-level administrative accounts are disabled through autonomous enforcement.

---

## 10. Structural Focus

This research evaluates autonomous enforcement as a structural decision model characterized by:

- Detection-threshold gating
- Cross-domain signal correlation
- Automated containment propagation
- Contextual blindness to organizational hierarchy
- Control-plane disruption potential

The emphasis is on decision architecture behavior rather than product implementation flaws.

---

## 11. Limitations

The following constraints apply to this study:

- Single vendor autonomous containment implementation evaluated.
- Internal detection confidence scoring is not observable.
- Lab-scale environment used for controlled experimentation.
- Adversarial behavior simulated through controlled tooling.
- Configuration assumptions may influence enforcement scope.
- Findings represent structural properties of detection-driven systems and should be generalized cautiously.

---

## 12. Scope of Generalization

Although experimentation is conducted using Microsoft Defender XDR and Attack Disruption, the structural model evaluated in this research applies to any autonomous security system characterized by:

- Detection-driven classification thresholds
- Automated containment execution
- Cross-entity correlation logic
- Lack of business-context awareness during enforcement

ADID is therefore framed as a class of systemic risk associated with autonomous defensive architectures rather than as a product-specific anomaly.

---
