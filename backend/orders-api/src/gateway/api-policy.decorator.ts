import { SetMetadata } from '@nestjs/common';
import type { ApiPolicyMetadata } from './api-policy.types';
import { API_POLICY_METADATA_KEY } from './api-policy.constants';

/** Declarative route policy (auth, tenant, permissions, rate limits — always evaluated when set). */
export const ApiPolicy = (policy: ApiPolicyMetadata) => SetMetadata(API_POLICY_METADATA_KEY, policy);
