from getpass import getpass

from django.conf import settings
from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.core.management.base import BaseCommand, CommandError


class Command(BaseCommand):
    help = "Interactively create the non-staff user used by Local Demo Login."

    def add_arguments(self, parser):
        parser.add_argument(
            "--username",
            default=settings.LOCAL_DEMO_USERNAME,
            help="Must match LOCAL_DEMO_USERNAME.",
        )

    def handle(self, *args, **options):
        username = str(options["username"]).strip()
        if not username:
            raise CommandError("Username cannot be empty.")
        if username != settings.LOCAL_DEMO_USERNAME:
            raise CommandError("Username must match LOCAL_DEMO_USERNAME.")

        user_model = get_user_model()
        existing = user_model.objects.filter(username=username).first()
        if existing is not None:
            if existing.is_staff or existing.is_superuser:
                raise CommandError(
                    "The existing demo username belongs to a staff account."
                )
            self.stdout.write(
                "The local demo user already exists; no changes were made. "
                f"Use 'python manage.py changepassword {username}' if needed."
            )
            return

        password = getpass("Local demo password: ")
        confirmation = getpass("Confirm password: ")
        if password != confirmation:
            raise CommandError("Passwords do not match.")

        user = user_model(
            username=username,
            is_active=True,
            is_staff=False,
            is_superuser=False,
        )
        try:
            validate_password(password, user=user)
        except ValidationError as exc:
            raise CommandError(" ".join(exc.messages)) from exc

        user.set_password(password)
        user.save()
        self.stdout.write(
            self.style.SUCCESS("Local demo user created as a non-staff account.")
        )
