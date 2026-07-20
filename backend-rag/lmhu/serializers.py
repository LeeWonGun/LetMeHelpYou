# lmhu/serializers.py

from rest_framework import serializers
from .models import QuestionAnswer

class QuestionAnswerSerializer(serializers.ModelSerializer):
    class Meta:
        model = QuestionAnswer
        fields = '__all__'
