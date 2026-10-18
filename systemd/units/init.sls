include:
  - systemd.reload

{% import_yaml 'systemd/units/unittypes.yaml' as unittypes %}

{% for unittype, units in pillar.get('systemd', {}).items()  %}
  {% if unittype in unittypes.get('Valid') %}
    {% for unit, unitconfig in units.items() %}
      {% set unit_status = 'disable' if unitconfig.enabled is defined and unitconfig.enabled == false else 'enable' %}
      {% set dropin = unitconfig.dropin | default(false) %}

systemd_systemd_units_file_{{ unit }}_{{ unittype }}:
  file.managed:
      {%- if dropin %}
    - name: /etc/systemd/system/{{ unit }}.{{ unittype }}.d/salt-override.conf
    - makedirs: True
      {%- else %}
    - name: /etc/systemd/system/{{ unit }}.{{ unittype }}
      {%- endif %}
    - template: jinja
    - source: salt://systemd/units/unit.jinja
    - context:
        config: {{ unitconfig|json }}
    - watch_in:
      - cmd: reload_systemd_configuration

{#- Declarative states: the former cmd.wait pair only ran when the unit file
    changed, so a unit disabled or stopped by hand was never brought back. #}
systemd_systemd_units_cmd_enable_or_disable_{{ unit }}_{{ unittype }}:
  service.{{ 'disabled' if unit_status == 'disable' else 'enabled' }}:
    - name: {{ unit }}.{{ unittype }}
    - require:
      - file: systemd_systemd_units_file_{{ unit }}_{{ unittype }}
      - cmd: reload_systemd_configuration

      {% if (unittype == 'service' or unittype == 'path') %}
        {% set activation_status = unitconfig.status if unitconfig.status is defined and unitconfig.status == 'start' else 'stop' %}
systemd_systemd_units_activate_or_deactivate_{{ unit }}_{{ unittype }}:
  service.{{ 'running' if activation_status == 'start' else 'dead' }}:
    - name: {{ unit }}.{{ unittype }}
    - require:
      - service: systemd_systemd_units_cmd_enable_or_disable_{{ unit }}_{{ unittype }}
      - cmd: reload_systemd_configuration
      {% endif %}
    {% endfor %}
  {% endif %}
{% endfor %}

