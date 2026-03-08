FROM ghcr.io/openclaw/openclaw:main

ENV DEBIAN_FRONTEND=noninteractive
ARG TZ=UTC
ENV TZ=${TZ}

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    xfce4 \
    xfce4-goodies \
    dbus-x11 \
    x11-utils \
    x11-xserver-utils \
    supervisor \
    python3 \
    python3-pip \
    xvfb \
    x11vnc \
    locales \
    chrony \
    chromium \
    && rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

RUN sed -i "/${LOCALE}/s/^# //g" /etc/locale.gen && locale-gen

RUN mkdir -p /opt/novnc/utils /opt/novnc/www

RUN wget -q https://github.com/novnc/noVNC/archive/refs/heads/main.tar.gz -O /tmp/novnc.tar.gz && \
    tar -xzf /tmp/novnc.tar.gz -C /opt/novnc && \
    mv /opt/novnc/noVNC-main/* /opt/novnc/www/ && \
    rm -rf /opt/novnc/noVNC-main /tmp/novnc.tar.gz

RUN wget -q https://github.com/novnc/websockify/archive/refs/heads/main.tar.gz -O /tmp/ws.tar.gz && \
    tar -xzf /tmp/ws.tar.gz -C /opt/novnc/utils/ && \
    mv /opt/novnc/websockify-main /opt/novnc/utils/websockify && \
    rm -rf /tmp/ws.tar.gz

RUN pip3 install --no-cache-dir numpy pillow websockify

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN mkdir -p /var/run/dbus /var/log/dbus && \
    dbus-daemon --system --fork || true

RUN useradd -m -s /bin/bash agent && \
    echo "agent:agent" | chpasswd && \
    mkdir -p /home/agent/.vnc && \
    echo "${VNC_PASSWORD}" | vncpasswd -f > /home/agent/.vnc/passwd && \
    chmod 600 /home/agent/.vnc/passwd && \
    chown -R agent:agent /home/agent

COPY xstartup /home/agent/.vnc/xstartup
RUN chmod +x /home/agent/.vnc/xstartup && \
    chown agent:agent /home/agent/.vnc/xstartup

RUN mkdir -p /home/agent/.config/xfce4 /home/agent/.config/xfce4/xfconf /home/agent/.config/xfce4/panel /home/agent/.config/menus

COPY xfce-applications.menu /home/agent/.config/menus/applications.menu
RUN chown -R agent:agent /home/agent/.config

RUN echo "allowed_users=anybody" > /etc/X11/Xwrapper.config && \
    echo "needs_root_rights=yes" >> /etc/X11/Xwrapper.config

EXPOSE 6080

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
