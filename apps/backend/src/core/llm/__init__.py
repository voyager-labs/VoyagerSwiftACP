"""LLM 통합 모듈"""

# LLM Provider (추상 인터페이스 + 구현체)
from core.llm.llm_provider import LLMProvider
from core.llm.langchain_provider import LangChainProvider
from core.llm.ollama_client import OllamaClient  # 레거시 지원

# 공통 유틸리티
from core.llm.query_converter import QueryConverter
from core.llm.registry_query_builder import RegistryQueryBuilder
from core.llm.query_validator import QueryValidator

# 5가지 쿼리 변환 방식
from core.llm.method1_separated_converter import SeparatedQueryConverter
from core.llm.method2_llm_only_converter import LLMOnlyQueryConverter
from core.llm.method3_two_stage_converter import TwoStageQueryConverter
from core.llm.method4_validated_converter import ValidatedQueryConverter
from core.llm.method5_self_correction_converter import SelfCorrectionQueryConverter

__all__ = [
    # LLM Provider
    "LLMProvider",
    "LangChainProvider",
    "OllamaClient",  # 레거시
    # 유틸리티
    "QueryConverter",
    "RegistryQueryBuilder",
    "QueryValidator",
    # 5가지 변환 방식
    "SeparatedQueryConverter",
    "LLMOnlyQueryConverter",
    "TwoStageQueryConverter",
    "ValidatedQueryConverter",
    "SelfCorrectionQueryConverter",
]
