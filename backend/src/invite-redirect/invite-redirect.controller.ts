import { Controller, Get, Header, Query } from '@nestjs/common';
import { ApiOperation, ApiQuery, ApiResponse, ApiTags } from '@nestjs/swagger';

@ApiTags('Invite')
@Controller('invite')
export class InviteRedirectController {
  @Get()
  @Header('Content-Type', 'text/html')
  @ApiOperation({
    summary: 'Redirect invite link to the mobile app via deep link',
  })
  @ApiQuery({ name: 'token', description: 'Invite token from the email' })
  @ApiResponse({
    status: 200,
    description: 'HTML page that redirects to the app',
  })
  redirect(@Query('token') token: string) {
    const mbtLink = `mbt://invite?token=${token}`;
    // Chrome on Android blocks JS redirects to custom schemes.
    // intent:// URI tells Chrome to launch the app directly.
    const intentLink = `intent://invite?token=${token}#Intent;scheme=mbt;package=com.example.rpi_bridge;end`;

    return `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Opening MBT App...</title>
    <style>
      body {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        min-height: 100vh;
        margin: 0;
        background-color: #f4f6f9;
        color: #1a1a2e;
      }
      .card {
        background: #fff;
        border-radius: 12px;
        padding: 40px;
        text-align: center;
        box-shadow: 0 4px 24px rgba(0,0,0,0.08);
        max-width: 360px;
        width: 90%;
      }
      h1 { font-size: 22px; margin-bottom: 12px; }
      p { color: #4a5568; font-size: 15px; line-height: 1.6; }
      a {
        display: inline-block;
        margin-top: 24px;
        background-color: #4f46e5;
        color: #fff;
        text-decoration: none;
        padding: 14px 32px;
        border-radius: 8px;
        font-weight: 600;
        font-size: 16px;
      }
    </style>
    <script>
      var isAndroid = /android/i.test(navigator.userAgent);
      var isIOS = /iphone|ipad|ipod/i.test(navigator.userAgent);

      window.onload = function () {
        if (isAndroid) {
          window.location.href = '${intentLink}';
        } else if (isIOS) {
          window.location.href = '${mbtLink}';
        }
      };
    </script>
  </head>
  <body>
    <div class="card">
      <h1>Opening MBT App...</h1>
      <p>You should be redirected to the app automatically.</p>
      <a href="${intentLink}">Tap here if the app doesn't open</a>
    </div>
  </body>
</html>`;
  }
}
